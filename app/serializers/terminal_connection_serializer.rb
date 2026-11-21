# Conexión con un proveedor de terminal (spec 069, contracts/api.md). Nunca incluye tokens.
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
      terminals_count: @connection.payment_terminals.count
    }
  end
end
