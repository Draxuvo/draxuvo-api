# app/controllers/api/v1/employees_controller.rb
module Api
  module V1
    class EmployeesController < BaseController
      include MembershipRules

      # checkin/checkout registran asistencia: dependen de :attendance, no de :employees.
      requires_module :employees, except: %i[checkin checkout]
      requires_module :attendance, only: %i[checkin checkout]
      # Marcar a otro y dar o quitar acceso es de administrador, dueño y super admin (spec 036).
      before_action :require_admin!, only: %i[checkin checkout grant_access update_access revoke_access]
      before_action :set_employee, only: %i[show update destroy checkin checkout active grant_access update_access revoke_access]

      def index
        employees = current_company.employees.includes(user: :user_companies).search(params[:search])
        employees = employees.where(status: params[:status]) if params[:status].present?
        employees = filter_by_access(employees)
        employees = apply_sort(employees, allowed: %i[name position department salary created_at], default: :name)
        @pagy, @employees = pagy(employees)
        serialized = serialize(@employees)
        render json: paginate_response(@pagy, serialized)
      end

      def show
        render json: serialize(@employee)
      end

      def create
        email = params.dig(:employee, :email).to_s.strip.downcase.presence
        # Dar acceso es de administrador y dueño; el gerente puede dar de alta al empleado, con su correo como dato de contacto.
        boss = Authorizable::ADMIN_ROLES.include?(current_role)
        require_admin! if params[:access].present?

        ActiveRecord::Base.transaction do
          employee = current_company.employees.build(employee_params.except(:email, :phone))
          employee.status = :active if employee_params[:status].blank?
          employee.phone = params.dig(:employee, :phone)
          employee.email = email unless boss
          employee.save!
          grant!(employee, email: email, role: params.dig(:access, :role), phone: params.dig(:employee, :phone)) if email && boss
          render json: serialize(employee.reload), status: :created
        end
      end

      def update
        @employee.update!(employee_params.except(:email, :phone))
        render json: @employee
      end

      def destroy
        ActiveRecord::Base.transaction do
          user = @employee.user
          @employee.destroy!
          user&.destroy!
        end
        render json: { message: I18n.t("employees.deleted") }
      end

      def active
        new_status = @employee.active? ? :inactive : :active
        @employee.update!(status: new_status)
        render json: serialize(@employee)
      end

      def checkin
        raise_inactive! unless @employee.active?

        at = parse_at
        created = mark.check_in(at: at, strict: true)
        render json: AttendanceSerializer.new(@employee.attendances.order(:id).last).as_json, status: created ? :created : :ok
      rescue Attendances::Mark::AlreadyOpen then mark_error("already_open", "employees.checkin_open")
      rescue Attendances::Mark::FutureTime  then mark_error("future_time", "attendance.future_time")
      rescue Attendances::Mark::Overlap     then mark_error("overlap", "attendance.overlap")
      end

      def checkout
        attendance = mark.check_out(at: parse_at, strict: true)
        render json: AttendanceSerializer.new(attendance).as_json
      rescue Attendances::Mark::NoOpenAttendance then mark_error("no_open_attendance", "attendance.no_open_for_employee")
      rescue Attendances::Mark::BeforeCheckin    then mark_error("before_checkin", "attendance.before_checkin")
      rescue Attendances::Mark::FutureTime       then mark_error("future_time", "attendance.future_time")
      rescue Attendances::Mark::Overlap          then mark_error("overlap", "attendance.overlap")
      end

      # POST /employees/:id/access — da acceso a un empleado que aún no lo tiene.
      def grant_access
        role = params[:role].presence
        email = params[:email].to_s.strip.downcase.presence || @employee.email
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("employees.email_required"), details: { code: "email_required" }) if email.blank?
        raise already_member_error if @employee.user_id

        ActiveRecord::Base.transaction { grant!(@employee, email: email, role: role, phone: params[:phone]) }
        render json: serialize(@employee.reload), status: :created
      end

      # PATCH /employees/:id/access — cambia el rol.
      def update_access
        membership = membership_of!(@employee)
        role = assignable_role!(params[:role])
        guard_target!(membership)
        ensure_another_owner!(membership) if membership.owner? && role != "owner"

        membership.update!(role: role)
        render json: serialize(@employee.reload)
      end

      # DELETE /employees/:id/access — quita el acceso; el empleado y su asistencia se conservan.
      def revoke_access
        membership = membership_of!(@employee)
        guard_target!(membership)
        ensure_another_owner!(membership) if membership.owner?

        membership.destroy! # suelta la ficha del usuario (UserCompany#release_employee)
        render json: serialize(@employee.reload)
      end

      private

      def set_employee
        @employee = current_company.employees.includes(:user).find(params[:id])
      end

      def employee_params
        params.require(:employee).permit(:name, :position, :department, :salary, :status, :email, :phone)
      end

      def mark
        @mark ||= Attendances::Mark.new(@employee, actor: current_user)
      end

      # Hora opcional de la marca; vacía = ahora. Una hora ilegible es 422 invalid_time.
      def parse_at
        return nil if params[:at].blank?

        Time.zone.parse(params[:at].to_s) || raise(ArgumentError)
      rescue ArgumentError
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("attendance.invalid_time"), details: { code: "invalid_time" })
      end

      def raise_inactive!
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("attendance.employee_inactive"), details: { code: "employee_inactive" })
      end

      def mark_error(code, key)
        render json: { error: { status: 422, code: code, message: I18n.t(key), details: { code: code } } },
               status: :unprocessable_entity
      end

      def serialize(resource)
        ActiveModelSerializers::SerializableResource.new(resource, include_access: Authorizable::ADMIN_ROLES.include?(current_role)).as_json
      end

      def filter_by_access(scope)
        case params[:access]
        when "with"    then scope.where.not(user_id: nil)
        when "without" then scope.where(user_id: nil)
        else scope
        end
      end

      def membership_of!(employee)
        membership = employee.user && current_company.user_companies.find_by(user_id: employee.user_id)
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("employees.no_access"), details: { code: "no_user" }) unless membership

        membership
      end

      def already_member_error
        ApiErrors::UnprocessableEntityError.new(message: I18n.t("company_members.already_member"), details: { code: "already_member" })
      end

      # Liga al empleado con un usuario (nuevo o existente) y su membresía con el rol pedido (default staff).
      def grant!(employee, email:, role:, phone:)
        role = assignable_role!(role.presence || "staff")
        user = User.find_by(email: email)
        raise already_member_error if user && (current_company.user_companies.exists?(user: user) || current_company.employees.where(user: user).exists?)

        new_user = user.nil?
        user ||= User.create!(
          **employee.parsed_name_parts, email: email, phone: phone.to_s,
          password: SecureRandom.hex(12), role: :staff, active: false
        )
        # Primero se liga la ficha: así la membresía no crea otra ficha para el mismo usuario.
        employee.update!(user: user, email: (Employee.where(email: email).where.not(id: employee.id).exists? ? nil : email), phone: phone.presence || employee.phone)
        current_company.user_companies.create!(user: user, role: role)
        send_set_password_email(user) if new_user
      end
    end
  end
end
