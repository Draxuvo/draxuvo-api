# Conexión con un proveedor de terminal (spec 069, contracts/api.md). Nunca incluye tokens ni la clave secreta: de una
# conexión con credenciales propias solo dice los últimos 4 del token, si hay clave secreta y la URL de sus avisos.
class TerminalConnectionSerializer
  def initialize(connection)
    @connection = connection
  end

  def as_json(*)
    return nil unless @connection

    {
      id: @connection.id, provider: @connection.provider, status: @connection.status,
      account_label: @connection.account_label, live_mode: @connection.live_mode,
      connected_at: @connection.connected_at, disconnected_at: @connection.disconnected_at,
      connected_by: @connection.connected_by && { id: @connection.connected_by.id, name: @connection.connected_by.full_name },
      error_code: @connection.error_code, error_message: @connection.error_message,
      terminals_count: @connection.payment_terminals.count,
      auth_method: @connection.auth_method, **own_credentials
    }
  end

  private

  def own_credentials
    return {} unless @connection.own_credentials?

    token = @connection.connected? || @connection.error? ? @connection.token : nil
    { token_hint: token.present? ? "…#{token.last(4)}" : nil, webhook_secret_present: @connection.signing_secret.present?,
      webhook_url: webhook_url }
  end

  def webhook_url
    return nil if @connection.webhook_token.blank?

    Rails.application.routes.url_helpers.api_v1_mercado_pago_connection_webhook_url(token: @connection.webhook_token)
  end
end
