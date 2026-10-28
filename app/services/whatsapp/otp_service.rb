module Whatsapp
  class OtpService
    OTP_TTL      = 10.minutes
    CACHE_PREFIX = "whatsapp_otp"

    def initialize(phone)
      @phone = sanitize_phone(phone)
    end

    # Genera un OTP, lo guarda en cache y lo envía por WhatsApp.
    # Retorna el código generado (útil para tests).
    def send_code
      # Spec 039: en una demo no se envía nada; el código es fijo para que la verificación siga funcionando.
      if Demo::Guard.active?
        store_code(Demo::Guard::DEMO_OTP)
        return Demo::Guard::DEMO_OTP
      end

      ensure_available!
      code = generate_code
      store_code(code)
      deliver(code)
      log(:info, "OTP sent phone=#{@phone} ttl=#{OTP_TTL / 60}min")
      code
    end

    # Compara el código ingresado con el guardado en cache.
    def verify(code)
      stored = Rails.cache.read(cache_key)

      if stored.nil?
        log(:warn, "OTP expired or not found phone=#{@phone}")
        return { verified: false, error: "El código expiró o no existe. Solicita uno nuevo." }
      end

      if stored != code.to_s.strip
        log(:warn, "OTP mismatch phone=#{@phone}")
        return { verified: false, error: "Código incorrecto." }
      end

      Rails.cache.delete(cache_key)
      log(:info, "OTP verified phone=#{@phone}")
      { verified: true }
    end

    private

    # Spec 047: la configuración sale de `Whatsapp::Config` (panel primero, variables de entorno de respaldo).
    def config = @config ||= Whatsapp::Config.current

    def generate_code
      SecureRandom.random_number(100_000..999_999).to_s
    end

    def store_code(code)
      Rails.cache.write(cache_key, code, expires_in: OTP_TTL)
    end

    def deliver(code)
      template = config.template_for(:verification_code)
      payload = {
        messaging_product: "whatsapp",
        to:                @phone,
        type:              "template",
        template: {
          name:       template.name,
          language:   { code: template.language },
          components: [ { type: "body", parameters: [ { type: "text", text: code } ] } ]
        }
      }

      result = config.client.post("/#{config.phone_number_id}/messages", payload)
      return delivered(result) if result.ok?

      fail_delivery!(result.failure)
    end

    def delivered(result)
      Whatsapp::Health.record_success(:verification_code)
      log(:info, "OTP delivered message_id=#{result.data.dig('messages', 0, 'id')} to=#{@phone}")
    end

    def fail_delivery!(failure)
      Whatsapp::Health.record_failure(:verification_code, failure)
      log(:error, "OTP delivery failed: family=#{failure.family} code=#{failure.code}")
      raise ApiErrors::UnprocessableEntityError.new(details: failure.user_message)
    end

    def cache_key
      "#{CACHE_PREFIX}:#{@phone}"
    end

    def sanitize_phone(phone)
      phone.to_s.gsub(/\D/, "")
    end

    # El canal apagado, sin conexión o sin plantilla aprobada se comporta como siempre: «no disponible por ahora».
    # Al cliente solo se le dice eso; el motivo va al registro.
    def ensure_available!
      return if config.available?(:verification_code)

      log(:warn, "WhatsApp no disponible para códigos de verificación (origen=#{config.source})")
      raise ApiErrors::UnprocessableEntityError.new(details: I18n.t("whatsapp.not_configured"))
    end

    def log(level, msg)
      tagged = "[Whatsapp::OtpService] #{msg}"
      Rails.logger.public_send(level, tagged)
    end
  end
end
