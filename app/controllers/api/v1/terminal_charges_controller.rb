module Api
  module V1
    # Solicitudes de cobro en terminales integradas (spec 069, contracts/api.md). Las crea quien puede cobrar (las reglas
    # del cobro de siempre, incluida la spec 058); las ve y las cancela quien la creó o un jefe. Un reintento de `create`
    # sobre el mismo cobro responde 409 `terminal_charge_pending` con el id de la abierta, para retomarla (no usa el
    # concern Idempotent: la llamada al proveedor no debe quedar dentro de una transacción).
    class TerminalChargesController < BaseController
      requires_module :terminals
      before_action :set_charge, only: %i[show cancel abandon]
      before_action :require_admin!, only: %i[index]

      SYNC_EVERY = 10.seconds

      # GET /terminal_charges?status=unapplied|all — jefes (pagos sin aplicar e historial).
      def index
        scope = current_company.terminal_charges.includes(:payment_terminal, :created_by, :terminal_refund).order(created_at: :desc)
        scope = scope.where(status: params[:status].presence || "unapplied") unless params[:status] == "all"
        scope = scope.where(payment_terminal_id: params[:terminal_id]) if params[:terminal_id].present?
        scope = scope.where(created_at: Date.parse(params[:from]).beginning_of_day..) if params[:from].present?
        scope = scope.where(created_at: ..Date.parse(params[:to]).end_of_day) if params[:to].present?
        scope = search(scope, params[:search]) if params[:search].present?
        @pagy, charges = pagy(scope)
        render json: paginate_response(@pagy, charges.map { |charge| serialize(charge) })
      rescue Date::Error
        raise ApiErrors::UnprocessableEntityError.new(details: { code: "invalid_date" })
      end

      # POST /terminal_charges
      def create
        charge = TerminalCharges::Create.call(company: current_company, user: current_user, params: params)
        render json: serialize(charge), status: :created
      end

      # GET /terminal_charges/:id — si sigue abierta y lleva rato sin consultarse, pide consultarla (research R5).
      def show
        stale = @charge.last_synced_at.nil? || @charge.last_synced_at < SYNC_EVERY.ago
        if stale && (@charge.open? || TerminalCharge::LATE.include?(@charge.status)) && @charge.provider_order_id.present?
          @charge.update_columns(last_synced_at: Time.current)
          ::TerminalCharges::SyncJob.perform_later(@charge.id)
        end
        render json: serialize(@charge)
      end

      # POST /terminal_charges/:id/cancel
      def cancel
        render json: serialize(TerminalCharges::Cancel.call(@charge, user: current_user))
      end

      # POST /terminal_charges/:id/abandon — respaldo manual (US3).
      def abandon
        render json: serialize(TerminalCharges::Abandon.call(@charge, user: current_user))
      end

      private

      def boss? = Authorizable::ADMIN_ROLES.include?(current_role)

      # Quien la creó o un jefe.
      def set_charge
        @charge = current_company.terminal_charges.find(params[:id])
        forbid! unless boss? || @charge.created_by_id == current_user.id
      end

      def serialize(charge) = TerminalChargeSerializer.new(charge, boss: boss?, user: current_user).as_json

      def search(scope, query)
        q = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
        scope.left_joins(:payment_terminal)
             .where("terminal_charges.provider_reference ILIKE :q OR terminal_charges.provider_order_id ILIKE :q OR payment_terminals.name ILIKE :q", q: q)
      end
    end
  end
end
