# Guarda un intento de inicio de sesión en la bitácora (spec 073, research R1). Nunca recibe la contraseña y nunca hace
# fallar el login: si guardar falla, lo reporta a Sentry, deja una línea en el log sin el correo y sigue.
module LoginAttempts
  class Record
    CLIENT_HEADER = "X-Draxuvo-Client".freeze
    VERSION_HEADER = "X-Draxuvo-Client-Version".freeze

    def self.call(request:, email:, result:, user: nil)
      new(request).call(email: email, result: result, user: user)
    end

    def initialize(request)
      @request = request
    end

    def call(email:, result:, user:)
      LoginAttempt.create!(
        result: result, email: email.to_s.strip.downcase[0, 254], user: user, ip: client_ip,
        user_agent: user_agent.presence&.slice(0, 500), channel: channel,
        client_version: @request.headers[VERSION_HEADER].to_s.strip.presence&.slice(0, 50), demo: demo?(user)
      )
    rescue StandardError => error
      Sentry.capture_exception(error)
      Rails.logger.error("[LoginAttempts::Record] no se guardó: #{error.class}")
      nil
    end

    private

    def user_agent = @request.user_agent.to_s

    # research R3: el encabezado del cliente gana; si no, el User-Agent nativo es la app y el de navegador es el panel.
    def channel
      declared = @request.headers[CLIENT_HEADER].to_s.strip.downcase
      return declared if %w[panel app].include?(declared)
      return "app" if UserAgentSummary.native_app?(user_agent)
      return "panel" if UserAgentSummary.browser?(user_agent)

      "unknown"
    end

    def client_ip
      IPAddr.new(@request.remote_ip.to_s).to_s
    rescue IPAddr::Error
      nil
    end

    # research R4: solo si tiene membresías y todas son de empresas de demo.
    def demo?(user)
      return false unless user

      memberships = Company.joins(:user_companies).where(user_companies: { user_id: user.id })
      memberships.exists? && !memberships.where(demo: false).exists?
    end
  end
end
