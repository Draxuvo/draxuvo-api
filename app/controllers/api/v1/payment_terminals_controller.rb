module Api
  module V1
    # Terminales de cobro del negocio (spec 015): las activas las ve cualquiera con sesión para cobrar;
    # las configura el admin o el dueño (FR-018). Son pocas por empresa, así que no se paginan.
    # Es un módulo del plan (spec 030): fuera de Pro y Empresa, o desactivado por el super admin, todo es 403.
    # Spec 069: `create` con `terminal_connection_id` + `device_id` liga un dispositivo del proveedor (terminal integrada);
    # `prepare` lo vuelve a dejar en modo de cobro desde un sistema y `unlink` la deja manual.
    class PaymentTerminalsController < BaseController
      requires_module :terminals
      before_action :require_admin!, only: %i[create update destroy prepare unlink]

      def index
        scope = current_company.payment_terminals.includes(:terminal_connection).order(:name)
        scope = scope.active unless admin? && ActiveModel::Type::Boolean.new.cast(params[:include_inactive])
        render json: { results: scope.map { |terminal| serialize(terminal) } }
      end

      def create
        link = params.require(:payment_terminal).permit(:name, :terminal_connection_id, :device_id)
        if link[:terminal_connection_id].present? || link[:device_id].present?
          result = PaymentTerminals::Link.call(company: current_company, user: current_user, connection_id: link[:terminal_connection_id],
                                               device_id: link[:device_id], name: link[:name])
          return render json: serialize(result.terminal, restart_required: result.restart_required), status: :created
        end

        terminal = current_company.payment_terminals.create!(terminal_params)
        render json: serialize(terminal), status: :created
      end

      # POST /payment_terminals/:id/prepare — { mode, restart_required }
      def prepare
        terminal = current_company.payment_terminals.find(params[:id])
        preparation = PaymentTerminals::Link.prepare!(terminal, user: current_user)
        render json: { mode: preparation.mode, restart_required: preparation.restart_required }
      end

      # POST /payment_terminals/:id/unlink — la deja manual; sus pagos no cambian.
      def unlink
        terminal = current_company.payment_terminals.find(params[:id])
        ensure_no_open_charge!(terminal)
        connection = terminal.terminal_connection
        terminal.unlink!
        TerminalEvent.log!(:device_unlinked, terminal: terminal, connection: connection, user: current_user)
        render json: serialize(terminal)
      end

      def update
        terminal = current_company.payment_terminals.find(params[:id])
        ensure_no_open_charge!(terminal) if terminal_params[:active].to_s == "false"
        terminal.update!(terminal_params)
        render json: serialize(terminal)
      end

      # Con cobros no se borra: la pantalla ofrece desactivarla (FR-019).
      def destroy
        terminal = current_company.payment_terminals.find(params[:id])
        ensure_no_open_charge!(terminal)
        unless terminal.destroy
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("payment_terminal.in_use"), details: { code: "terminal_in_use" }
          )
        end

        render json: serialize(terminal)
      end

      private

      # Con una solicitud de cobro abierta no se desactiva, borra ni desliga (spec 069).
      def ensure_no_open_charge!(terminal)
        return unless terminal.terminal_charges.open.exists?

        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("terminal_charge.errors.terminal_charge_pending"), details: { code: "terminal_charge_pending" }
        )
      end

      def admin?
        Authorizable::ADMIN_ROLES.include?(current_role)
      end

      def serialize(terminal, restart_required: nil)
        PaymentTerminalSerializer.new(terminal, admin: admin?, restart_required: restart_required).as_json
      end

      def terminal_params
        params.require(:payment_terminal).permit(:name, :provider, :active)
      end
    end
  end
end
