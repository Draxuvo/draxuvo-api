require "net/http"
require "json"

module Whatsapp
  class OtpService
    GRAPH_API_VERSION = "v25.0"
    GRAPH_BASE        = "https://graph.facebook.com"
    OTP_TTL           = 10.minutes
    CACHE_PREFIX      = "whatsapp_otp"

    def initialize(phone)
      @phone = sanitize_phone(phone)
    end

    # Genera un OTP, lo guarda en cache y lo envía por WhatsApp.
    # Retorna el código generado (útil para tests).
    def send_code
      validate_config!
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

    def generate_code
      SecureRandom.random_number(100_000..999_999).to_s
    end

    def store_code(code)
      Rails.cache.write(cache_key, code, expires_in: OTP_TTL)
    end

    def deliver(code)
      payload = {
        messaging_product: "whatsapp",
        to:                @phone,
        type:              "template",
        template: {
          name:     ENV.fetch("WHATSAPP_OTP_TEMPLATE_NAME", "verification_code"),
          language: { code: ENV.fetch("WHATSAPP_OTP_TEMPLATE_LANG", "es_MX") },
          components: [
            {
              type:       "body",
              parameters: [ { type: "text", text: code } ]
            }
          ]
        }
      }

      result = request(
        path:         "/#{phone_number_id}/messages",
        body:         payload.to_json,
        content_type: "application/json"
      )

      log(:info, "OTP delivered message_id=#{result.dig('messages', 0, 'id')} to=#{@phone}")
      result
    end

    def request(path:, body:, content_type:)
      uri = URI("#{GRAPH_BASE}/#{GRAPH_API_VERSION}#{path}")

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 30

      req                  = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"]  = content_type
      req.body             = body

      res  = http.request(req)
      data = JSON.parse(res.body)

      log(:info, "POST #{uri} HTTP=#{res.code} body=#{data.to_json}")

      unless res.is_a?(Net::HTTPSuccess)
        msg = data.dig("error", "message") || "WhatsApp API error (HTTP #{res.code})"
        log(:error, "OTP delivery failed: #{msg}")
        raise ApiErrors::UnprocessableEntityError.new(details: msg)
      end

      data
    end

    def cache_key
      "#{CACHE_PREFIX}:#{@phone}"
    end

    def sanitize_phone(phone)
      phone.to_s.gsub(/\D/, "")
    end

    def validate_config!
      missing = []
      missing << "WHATSAPP_ACCESS_TOKEN"   unless ENV["WHATSAPP_ACCESS_TOKEN"].present?
      missing << "WHATSAPP_PHONE_NUMBER_ID" unless ENV["WHATSAPP_PHONE_NUMBER_ID"].present?
      return if missing.empty?

      # WhatsApp está desactivado en el lanzamiento (spec 012): al cliente solo se le dice que no está
      # disponible; los nombres de las variables van al log, no a la respuesta.
      log(:warn, "WhatsApp no configurado, faltan: #{missing.join(', ')}")
      raise ApiErrors::UnprocessableEntityError.new(details: I18n.t("whatsapp.not_configured"))
    end

    def log(level, msg)
      tagged = "[Whatsapp::OtpService] #{msg}"
      Rails.logger.public_send(level, tagged)
    end

    def phone_number_id
      ENV["WHATSAPP_PHONE_NUMBER_ID"]
    end

    def access_token
      ENV["WHATSAPP_ACCESS_TOKEN"]
    end
  end
end
