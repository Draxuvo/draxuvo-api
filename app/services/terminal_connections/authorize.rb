module TerminalConnections
  # Inicio de la autorización OAuth con PKCE (spec 069, research R2): guarda `state` y `code_verifier` 10 minutos en la
  # caché, ligados a la empresa y al usuario, y devuelve la URL del proveedor. `Connect` los consume una sola vez.
  class Authorize
    TTL = 10.minutes

    def self.call(company:, user:, provider:) = new(company, user, provider).call

    def self.cache_key(state) = "terminal_oauth:#{Digest::SHA256.hexdigest(state.to_s)}"

    def initialize(company, user, provider)
      @company = company
      @user = user
      @provider = provider
    end

    def call
      Demo::Guard.restrict!(:terminal_connection)
      client = TerminalProviders.for(@provider)
      unless client.available?
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("terminal_connection.errors.provider_unavailable"), details: { code: "provider_unavailable" }
        )
      end

      state = SecureRandom.urlsafe_base64(32)
      verifier = SecureRandom.urlsafe_base64(64)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      Rails.cache.write(self.class.cache_key(state),
                        { "company_id" => @company.id, "user_id" => @user.id, "provider" => @provider, "verifier" => verifier },
                        expires_in: TTL)
      client.authorize_url(state: state, code_challenge: challenge)
    end
  end
end
