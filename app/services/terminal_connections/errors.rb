module TerminalConnections
  # Traducción de los errores del proveedor a errores de la API, compartida por conexiones, terminales y cobros (spec 069).
  # Un error de conexión deja la conexión «Con error» (y avisa) antes de responder.
  module Errors
    module_function

    def ensure_connected!(connection)
      return if connection&.connected?

      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("terminal_connection.errors.connection_error"), details: { code: "connection_error" }
      )
    end

    # Corre el bloque y traduce `TerminalProviders::Error`: conexión → 422 `connection_error`; caído → 502
    # `provider_unavailable`; los demás los devuelve a quien llama para que decida.
    def wrap(connection)
      yield
    rescue TerminalProviders::Error => e
      raise unless e.failure.connection? || e.failure.transient?

      if e.failure.connection?
        Health.failed!(connection, e.failure)
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("terminal_connection.errors.connection_error"), details: { code: "connection_error" }
        )
      end
      raise ApiErrors::BaseError.new(status: 502, message: I18n.t("terminal_connection.errors.provider_down"),
                                     details: { code: "provider_unavailable" })
    end
  end
end
