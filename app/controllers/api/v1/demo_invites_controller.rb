# Contrato: specs/039-demo-por-plan/contracts/api.md (/demo_invites).
# El equipo comercial (super admin) genera enlaces de invitación a la demo, los revoca y ve cuántas veces se abrieron.
# `resolve` es público: dice qué plan abre un enlace sin crear nada.
module Api
  module V1
    class DemoInvitesController < BaseController
      skip_before_action :authenticate_request, :enter_demo_context, :check_subscription!, only: :resolve
      before_action :require_super_admin!, except: :resolve

      # GET /api/v1/demo_invites
      def index
        invites = filter(DemoInvite.includes(:created_by)).order(id: :desc)
        @pagy, invites = pagy(invites)
        stats = DemoInviteSerializer.stats_for(invites)
        render json: paginate_response(@pagy, invites.map { |invite| DemoInviteSerializer.new(invite, stats: stats).as_json })
      end

      # POST /api/v1/demo_invites
      def create
        days = days_param
        invite, token = DemoInvite.issue!(plan: params[:plan], scenario: params[:scenario], label: params[:label],
                                          created_by: current_user, expires_at: days.days.from_now)
        render json: DemoInviteSerializer.new(invite, reveal: { token: token, url: invite_url(token) }).as_json,
               status: :created
      end

      # POST /api/v1/demo_invites/:id/revoke (idempotente)
      def revoke
        invite = DemoInvite.find(params[:id]).revoke!
        render json: DemoInviteSerializer.new(invite, stats: DemoInviteSerializer.stats_for([ invite ])).as_json
      end

      # GET /api/v1/demo_invites/resolve?token=
      def resolve
        invite = DemoInvite.find_by_token(params[:token])
        raise ApiErrors::NotFoundError.new(details: { code: "invite_not_found", message: I18n.t("demo.errors.invite_not_found") }) unless invite

        case invite.status
        when "revoked" then raise gone(:invite_revoked)
        when "expired" then raise gone(:invite_expired)
        end
        render json: { plan: invite.plan, scenario: invite.scenario }
      end

      private

      def filter(scope)
        scope = scope.where(plan: params[:plan]) if params[:plan].present?
        scope = scope.where("label ILIKE ?", "%#{DemoInvite.sanitize_sql_like(params[:search])}%") if params[:search].present?
        case params[:status]
        when "active" then scope.active
        when "revoked" then scope.where.not(revoked_at: nil)
        when "expired" then scope.where(revoked_at: nil).where("expires_at <= ?", Time.current)
        else scope
        end
      end

      def days_param
        return Demo::Config.invite_days if params[:expires_in_days].blank?

        days = params[:expires_in_days].to_i
        raise ApiErrors::BadRequestError.new(details: I18n.t("demo.errors.invalid_contact")) unless (1..60).cover?(days)

        days
      end

      def invite_url(token) = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:4200').chomp('/')}/es/demo/#{token}"

      def gone(code)
        ApiErrors::GoneError.new(message: I18n.t("demo.errors.#{code}"), details: { code: code.to_s })
      end
    end
  end
end
