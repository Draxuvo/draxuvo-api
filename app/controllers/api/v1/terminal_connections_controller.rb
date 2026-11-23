module Api
  module V1
    # Conexiones con proveedores de terminal (spec 069, contracts/api.md): solo dueño y administrador, con el módulo
    # `terminals`. Dos formas de conectar: OAuth (`authorize` da la URL del proveedor y `callback` recibe el código que la
    # página de regreso de `ui` reenvía con la sesión del usuario), solo si la plataforma tiene su aplicación, y
    # credenciales propias (`credentials`: el Access Token de la aplicación del negocio). Nunca se devuelven tokens.
    class TerminalConnectionsController < BaseController
      requires_module :terminals
      before_action :require_admin!

      # GET /terminal_connections
      def index
        connections = current_company.terminal_connections.includes(:connected_by).index_by(&:provider)
        providers = TerminalProviders.providers.map do |provider|
          client = TerminalProviders.for(provider)
          { provider: provider, available: client.available? || client.own_credentials?, oauth: client.available?,
            own_credentials: client.own_credentials?, connection: TerminalConnectionSerializer.new(connections[provider]).as_json }
        end
        render json: { providers: providers }
      end

      # POST /terminal_connections/mercado_pago/authorize
      def authorize
        url = TerminalConnections::Authorize.call(company: current_company, user: current_user, provider: params[:provider])
        render json: { url: url }
      end

      # POST /terminal_connections/mercado_pago/callback — { code, state }
      def callback
        connection = TerminalConnections::Connect.call(company: current_company, user: current_user, provider: params[:provider],
                                                       code: params[:code], state: params[:state])
        render json: TerminalConnectionSerializer.new(connection).as_json
      end

      # PUT /terminal_connections/mercado_pago/credentials — { access_token, webhook_secret }
      def credentials
        connection = TerminalConnections::ConnectWithToken.call(company: current_company, user: current_user, provider: params[:provider],
                                                                access_token: params[:access_token], webhook_secret: params[:webhook_secret])
        render json: TerminalConnectionSerializer.new(connection).as_json
      end

      # DELETE /terminal_connections/:id
      def destroy
        connection = current_company.terminal_connections.find(params[:id])
        if connection.terminal_charges.open.exists?
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("terminal_charge.errors.terminal_charge_pending"), details: { code: "terminal_charge_pending" }
          )
        end

        connection.disconnect!
        TerminalEvent.log!(:disconnected, connection: connection, user: current_user)
        render json: TerminalConnectionSerializer.new(connection).as_json
      end

      # GET /terminal_connections/:id/devices — paginado por el proveedor (page, page_size ≤ 50, search).
      def devices
        connection = current_company.terminal_connections.find(params[:id])
        result = TerminalConnections::Devices.call(connection, page: params[:page], page_size: params[:page_size], search: params[:search])
        pages = [ (result.total.to_f / result.page_size).ceil, 1 ].max
        from = result.devices.empty? ? 0 : ((result.page - 1) * result.page_size) + 1
        render json: {
          info: { page_size: result.page_size, page_index: result.page, total: result.total, page_start: from,
                  page_end: from.zero? ? 0 : from + result.devices.size - 1, pages_total: pages },
          results: result.devices
        }
      end
    end
  end
end
