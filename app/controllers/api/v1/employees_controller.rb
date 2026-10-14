# app/controllers/api/v1/employees_controller.rb
module Api
  module V1
    class EmployeesController < BaseController
      # checkin/checkout registran asistencia: dependen de :attendance, no de :employees.
      requires_module :employees, except: %i[checkin checkout]
      requires_module :attendance, only: %i[checkin checkout]
      before_action :set_employee, only: [ :show, :update, :destroy, :checkin, :checkout, :active ]

      def index
        employees = current_company.employees.includes(:user).search(params[:search])
        employees = employees.where(status: params[:status]) if params[:status].present?
        employees = apply_sort(employees, allowed: %i[name position department salary created_at], default: :name)
        @pagy, @employees = pagy(employees)
        serialized = ActiveModelSerializers::SerializableResource.new(@employees).as_json
        render json: paginate_response(@pagy, serialized)
      end

      def show
        render json: @employee
      end

      def create
        ActiveRecord::Base.transaction do
          email = params.dig(:employee, :email)
          phone = params.dig(:employee, :phone)
          employee = current_company.employees.build(employee_params.except(:email, :phone, :status))

          if email.present?
            user = User.create!(
              **employee.parsed_name_parts,
              email:    email,
              phone:    phone.to_s,
              password: SecureRandom.hex(12),
              role:     :staff,
              active:   false
            )
            employee.user  = user
            employee.email = email
            employee.phone = phone
            current_company.user_companies.find_or_create_by!(user: user)
            send_set_password_email(user)
          end

          employee.save!
          render json: ActiveModelSerializers::SerializableResource.new(employee).as_json, status: :created
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
        render json: ActiveModelSerializers::SerializableResource.new(@employee).as_json
      end

      def checkin
        open = @employee.attendances.where(checkout_at: nil).exists?
        if open
          return render json: { error: I18n.t("employees.checkin_open") },
                        status: :unprocessable_entity
        end

        attendance = @employee.attendances.create!(
          company:         current_company,
          checkin_at:      Time.current,
          lat:             params[:lat],
          lng:             params[:lng],
          attendance_type: :normal
        )
        render json: attendance, status: :created
      end

      def checkout
        attendance = @employee.attendances
                              .where(checkout_at: nil)
                              .order(checkin_at: :desc)
                              .first

        if attendance.nil?
          return render json: { error: I18n.t("employees.no_checkin") },
                        status: :unprocessable_entity
        end

        attendance.update!(checkout_at: Time.current)
        render json: attendance
      end

      private

      def set_employee
        @employee = current_company.employees.includes(:user).find(params[:id])
      end

      def employee_params
        params.require(:employee).permit(:name, :position, :department, :salary, :status, :email, :phone)
      end

      def send_set_password_email(user)
        Email::SetPasswordService.new(user, company_name: current_company.name).call
      rescue => e
        Rails.logger.error "[EmployeesController] SetPasswordService error: #{e.message}"
      end
    end
  end
end
