# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/company/members"). R14, FR-020, FR-021, FR-026.
# Personas de la empresa activa, para owner y admin. Reglas:
# - nadie asigna un rol mayor al suyo ni super_admin (403 role_not_allowed);
# - solo un owner asigna o quita owner, y nadie toca a alguien de rango mayor (403);
# - no se quita ni se baja al último owner (422 last_owner), salvo el super admin (spec 028).
module Api
  module V1
    class CompanyMembersController < BaseController
      before_action :require_admin!
      before_action :set_membership, only: %i[update destroy]

      # GET /api/v1/company/members
      def index
        memberships = current_company.user_companies.includes(:user).order(:id)
        @pagy, memberships = pagy(memberships)
        render json: paginate_response(@pagy, memberships.map { |m| CompanyMemberSerializer.new(m).as_json })
      end

      # POST /api/v1/company/members
      def create
        role = assignable_role!(requested_role.presence || "staff")
        email = member_params[:email].to_s.strip.downcase
        user = User.find_by(email: email)

        if user && current_company.user_companies.exists?(user: user)
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("company_members.already_member"),
            details: { code: "already_member" }
          )
        end

        email_sent = true
        membership = ActiveRecord::Base.transaction do
          new_user = user.nil?
          user ||= User.create!(member_params.slice(:first_name, :last_name, :phone).to_h
                                  .merge(email: email, password: SecureRandom.hex(12), active: true))
          created = current_company.user_companies.create!(user: user, role: role)
          email_sent = send_set_password_email(user) if new_user
          created
        end

        render json: CompanyMemberSerializer.new(membership).as_json.merge(email_sent: email_sent), status: :created
      end

      # PATCH /api/v1/company/members/:user_id
      def update
        role = assignable_role!(requested_role)
        guard_target!
        ensure_another_owner! if @membership.owner? && role != "owner"

        @membership.update!(role: role)
        render json: CompanyMemberSerializer.new(@membership).as_json
      end

      # DELETE /api/v1/company/members/:user_id — quita la membresía, no borra al usuario.
      def destroy
        guard_target!
        ensure_another_owner! if @membership.owner?

        @membership.destroy!
        render json: { message: I18n.t("company_members.removed") }
      end

      private

      def set_membership
        @membership = current_company.user_companies.includes(:user).find_by(user_id: params[:user_id])
        raise ApiErrors::NotFoundError.new(message: I18n.t("users.not_found")) unless @membership
      end

      def member_params
        params.require(:member).permit(:email, :first_name, :last_name, :phone)
      rescue ActionController::ParameterMissing => e
        raise ApiErrors::BadRequestError.new(message: e.message)
      end

      # El rol nunca pasa por mass assignment: se valida en assignable_role!.
      def requested_role
        member_params
        params[:member][:role].to_s
      end

      # Rol de empresa válido y no mayor al de quien lo asigna. super_admin nunca es asignable aquí.
      def assignable_role!(role)
        role = role.to_s
        return role if UserCompany.roles.key?(role) && UserCompany.rank(role) <= UserCompany.rank(current_role)

        forbid!(details: { code: "role_not_allowed", role: role })
      end

      # Nadie modifica a alguien de rango mayor; owner solo lo toca otro owner (o el super admin).
      def guard_target!
        return if UserCompany.rank(@membership.role) <= UserCompany.rank(current_role)

        forbid!(details: { code: "role_not_allowed", role: @membership.role })
      end

      def ensure_another_owner!
        return if current_role == "super_admin"
        return if current_company.user_companies.owner.where.not(id: @membership.id).exists?

        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("company_members.last_owner"),
          details: { code: "last_owner" }
        )
      end

      def send_set_password_email(user)
        Email::SetPasswordService.new(user, company_name: current_company.name).call[:success]
      rescue => e
        Rails.logger.error "[CompanyMembersController] SetPasswordService error class=#{e.class} message=#{e.message}"
        false
      end
    end
  end
end
