# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/company/members"). R14, FR-020, FR-021, FR-026.
# Personas de la empresa activa, para owner y admin. Reglas:
# - nadie asigna un rol mayor al suyo ni super_admin (403 role_not_allowed);
# - solo un owner asigna o quita owner, y nadie toca a alguien de rango mayor (403);
# - no se quita ni se baja al último owner (422 last_owner), salvo el super admin (spec 029).
module Api
  module V1
    class CompanyMembersController < BaseController
      include MembershipRules

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
    end
  end
end
