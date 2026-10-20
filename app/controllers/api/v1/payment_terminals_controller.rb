module Api
  module V1
    # Terminales de cobro del negocio (spec 015): las activas las ve cualquiera con sesión para cobrar;
    # las configura el admin o el dueño (FR-018). Son pocas por empresa, así que no se paginan.
    class PaymentTerminalsController < BaseController
      before_action :require_admin!, only: %i[create update destroy]

      def index
        scope = current_company.payment_terminals.order(:name)
        scope = scope.active unless admin? && ActiveModel::Type::Boolean.new.cast(params[:include_inactive])
        render json: { results: scope.map { |terminal| serialize(terminal) } }
      end

      def create
        terminal = current_company.payment_terminals.create!(terminal_params)
        render json: serialize(terminal), status: :created
      end

      def update
        terminal = current_company.payment_terminals.find(params[:id])
        terminal.update!(terminal_params)
        render json: serialize(terminal)
      end

      # Con cobros no se borra: la pantalla ofrece desactivarla (FR-019).
      def destroy
        terminal = current_company.payment_terminals.find(params[:id])
        unless terminal.destroy
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("payment_terminal.in_use"), details: { code: "terminal_in_use" }
          )
        end

        render json: serialize(terminal)
      end

      private

      def admin?
        Authorizable::ADMIN_ROLES.include?(current_role)
      end

      def serialize(terminal)
        PaymentTerminalSerializer.new(terminal, admin: admin?).as_json
      end

      def terminal_params
        params.require(:payment_terminal).permit(:name, :provider, :active)
      end
    end
  end
end
