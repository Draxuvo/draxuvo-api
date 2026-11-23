module TerminalConnections
  # Conexión con las credenciales de la aplicación propia del negocio (spec 069, credenciales propias): el dueño o
  # administrador pega el Access Token y, si configuró avisos, la clave secreta. Se comprueba el token con el proveedor
  # antes de guardarlo (cifrado, igual que con OAuth). Para cambiar solo la clave secreta se puede dejar el token vacío si
  # la conexión ya está hecha con credenciales propias.
  class ConnectWithToken
    TOKEN_FORMAT = /\A(APP_USR|TEST)-[A-Za-z0-9_-]{20,300}\z/

    def self.call(company:, user:, provider:, access_token:, webhook_secret:) =
      new(company, user, provider, access_token, webhook_secret).call

    def initialize(company, user, provider, access_token, webhook_secret)
      @company = company
      @user = user
      @provider = provider
      @access_token = access_token.to_s.strip
      @webhook_secret = webhook_secret.to_s.strip
    end

    def call
      Demo::Guard.restrict!(:terminal_connection)
      client = TerminalProviders.for(@provider)
      invalid!(:provider_unavailable) unless client.own_credentials?
      invalid!(:webhook_secret_invalid) if @webhook_secret.length > 200

      connection = @company.terminal_connections.find_or_initialize_by(provider: @provider)
      if @access_token.blank?
        invalid!(:access_token_missing) unless connection.persisted? && connection.own_credentials? && connection.connected?
        return update_secret(connection)
      end

      invalid!(:access_token_invalid) unless @access_token.match?(TOKEN_FORMAT)
      credentials = verify(client)
      connection.store_credentials!(credentials, user: @user, auth_method: "token")
      connection.update!(webhook_secret: @webhook_secret) if @webhook_secret.present?
      connection.ensure_webhook_token!
      Health.recovered!(connection)
      TerminalEvent.log!(:connected, connection: connection, user: @user, account_label: connection.account_label,
                                     live_mode: connection.live_mode, auth_method: "token")
      connection
    end

    private

    def update_secret(connection)
      invalid!(:access_token_missing) if @webhook_secret.blank?

      connection.update!(webhook_secret: @webhook_secret)
      connection.ensure_webhook_token!
      TerminalEvent.log!(:webhook_secret_changed, connection: connection, user: @user)
      connection
    end

    def verify(client)
      client.verify_token(@access_token)
    rescue TerminalProviders::Error => e
      Rails.logger.warn("[TerminalConnections::ConnectWithToken] #{e.failure.family} #{e.failure.reason}")
      code =
        if e.failure.reason == "point_not_enabled" then :point_not_enabled
        elsif e.failure.connection? then :access_token_rejected
        elsif e.failure.transient? then :provider_down
        else :access_token_rejected
        end
      invalid!(code)
    end

    def invalid!(code)
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("terminal_connection.errors.#{code}"), details: { code: code.to_s }
      )
    end
  end
end
