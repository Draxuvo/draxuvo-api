# Contrato: specs/039-demo-por-plan/contracts/api.md (/demo_sessions).
# Abrir una demo es público (como POST /registrations): crea una empresa de demostración efímera con datos de ejemplo.
# Hereda de BaseController porque salir de la demo y listar las aperturas sí necesitan sesión; la autenticación, el
# contexto de demo y la suscripción solo se omiten en `create`.
module Api
  module V1
    class DemoSessionsController < BaseController
      # En test el cache es null_store; las pruebas necesitan un store real para el límite.
      RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

      skip_before_action :authenticate_request, :check_subscription!, only: :create
      skip_before_action :enter_demo_context, only: %i[create finish]
      before_action :require_super_admin!, only: :index
      before_action :throttle_by_ip, only: :create

      # POST /api/v1/demo_sessions
      def create
        invite = usable_invite
        plan, scenario = invite ? [ invite.plan, invite.scenario ] : resolve_plan_and_scenario
        raise busy_error if DemoSession.active.count >= Demo::Config.max_active

        result = Demo::Provision.call(plan: plan, scenario: scenario, locale: locale, contact: contact_params, invite: invite)
        render json: {
          token: result.token, user: UserSerializer.new(result.user.reload), company_id: result.company.id,
          plan: plan, scenario: scenario, expires_at: result.session.expires_at
        }, status: :created
      rescue Demo::Busy
        raise busy_error
      end

      # DELETE /api/v1/demo_sessions/current — «Salir de la demo» o «Crear mi cuenta»: la termina y encola su borrado.
      def finish
        session = current_company.demo_session
        forbid!(details: { code: "not_a_demo" }) unless session&.user_id == current_user.id

        reason = params[:reason].to_s == "signup" ? "signup" : "left"
        session.update!(ended_at: Time.current, ended_reason: reason) unless session.ended?
        Demo::PurgeJob.perform_later(company_id: session.company_id)
        head :no_content
      end

      # GET /api/v1/demo_sessions — aperturas para el seguimiento comercial (super admin).
      def index
        sessions = filter(DemoSession.includes(:demo_invite)).order(id: :desc)
        @pagy, sessions = pagy(sessions)
        render json: paginate_response(@pagy, sessions.map { |session| DemoSessionSerializer.new(session).as_json })
      end

      private

      def filter(scope)
        scope = scope.where(plan: params[:plan]) if params[:plan].present?
        scope = scope.where(demo_invite_id: params[:demo_invite_id]) if params[:demo_invite_id].present?
        scope = scope.where("contact_name IS NOT NULL OR contact_email IS NOT NULL OR contact_phone IS NOT NULL") if params[:with_contact] == "true"
        scope = scope.where(created_at: Time.zone.parse(params[:from])..) if params[:from].present?
        scope = scope.where(created_at: ..Time.zone.parse(params[:to]).end_of_day) if params[:to].present?
        return scope if params[:search].blank?

        term = "%#{DemoSession.sanitize_sql_like(params[:search])}%"
        scope.where("contact_name ILIKE :term OR contact_email ILIKE :term", term: term)
      end

      # La invitación del enlace, si viene: 404 si no existe y 410 si venció o se revocó.
      def usable_invite
        return nil if params[:invite_token].blank?

        invite = DemoInvite.find_by_token(params[:invite_token])
        raise ApiErrors::NotFoundError.new(details: { code: "invite_not_found", message: I18n.t("demo.errors.invite_not_found") }) unless invite

        code = { "revoked" => :invite_revoked, "expired" => :invite_expired }[invite.status]
        raise ApiErrors::GoneError.new(message: I18n.t("demo.errors.#{code}"), details: { code: code.to_s }) if code

        invite
      end

      # Aperturas por IP y hora. El tope se lee en cada petición (Demo::Config) para poder cambiarlo sin reiniciar.
      def throttle_by_ip
        count = RATE_LIMIT_STORE.increment("demo_sessions:#{request.remote_ip}", 1, expires_in: 1.hour)
        return unless count && count > Demo::Config.rate_limit

        raise ApiErrors::TooManyRequestsError.new(message: I18n.t("demo.errors.rate_limited"))
      end

      def busy_error
        ApiErrors::ServiceUnavailableError.new(message: I18n.t("demo.errors.demo_busy"), details: { code: "demo_busy" })
      end

      def locale = DemoSession::LOCALES.include?(params[:locale].to_s) ? params[:locale].to_s : "es"

      def contact_params
        params[:contact].respond_to?(:permit) ? params[:contact].permit(:name, :email, :phone).to_h : {}
      end

      def resolve_plan_and_scenario
        plan = params[:plan].to_s
        bad_request!(:invalid_plan) unless Plan.keys.map(&:to_s).include?(plan)
        options = Demo::Scenarios.for_plan(plan)
        scenario = params[:scenario].presence&.to_s
        if scenario.nil?
          bad_request!(:scenario_required) if options.size > 1
          scenario = options.first
        else
          bad_request!(:invalid_scenario) unless options.include?(scenario)
        end
        [ plan, scenario ]
      end

      def bad_request!(key)
        raise ApiErrors::BadRequestError.new(details: I18n.t("demo.errors.#{key}"))
      end
    end
  end
end
