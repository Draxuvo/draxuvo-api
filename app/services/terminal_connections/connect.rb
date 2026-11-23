module TerminalConnections
  # Regreso de la autorización OAuth (spec 069, research R2): valida y consume el `state` (de este usuario y esta empresa),
  # canjea el código con PKCE y guarda la conexión cifrada. Reconectar reutiliza la misma fila. La misma cuenta del
  # proveedor puede estar conectada en varias empresas (principal y sucursales); lo que no se comparte es el dispositivo.
  class Connect
    def self.call(company:, user:, provider:, code:, state:) = new(company, user, provider, code, state).call

    def initialize(company, user, provider, code, state)
      @company = company
      @user = user
      @provider = provider
      @code = code.to_s
      @state = state.to_s
    end

    def call
      Demo::Guard.restrict!(:terminal_connection)
      stored = consume_state!
      credentials = exchange(stored["verifier"])

      connection = @company.terminal_connections.find_or_initialize_by(provider: @provider)
      connection.store_credentials!(credentials, user: @user, auth_method: "oauth")
      Health.recovered!(connection)
      TerminalEvent.log!(:connected, connection: connection, user: @user, account_label: connection.account_label,
                                     live_mode: connection.live_mode)
      connection
    end

    private

    def consume_state!
      key = Authorize.cache_key(@state)
      stored = @state.present? && @code.present? ? Rails.cache.read(key) : nil
      Rails.cache.delete(key) if stored
      valid = stored.is_a?(Hash) && stored["company_id"] == @company.id && stored["user_id"] == @user.id &&
              stored["provider"] == @provider
      invalid!(:invalid_state) unless valid
      stored
    end

    def exchange(verifier)
      TerminalProviders.for(@provider).exchange_code(code: @code, code_verifier: verifier)
    rescue TerminalProviders::Error => e
      Rails.logger.warn("[TerminalConnections::Connect] #{e.failure.family} #{e.failure.reason}")
      invalid!(:authorization_failed, reason: e.failure.reason)
    end

    def invalid!(code, **details)
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("terminal_connection.errors.#{code}"), details: { code: code.to_s, **details }
      )
    end
  end
end
