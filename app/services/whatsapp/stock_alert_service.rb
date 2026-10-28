require "net/http"
require "json"

module Whatsapp
  # Aviso de stock bajo por WhatsApp (spec 045). Lo inicia el negocio, así que fuera de la ventana de 24 h solo
  # sirve un mensaje de plantilla aprobada por Meta (WHATSAPP_STOCK_TEMPLATE_NAME). Sin configuración o sin plantilla
  # no falla: devuelve `unavailable` y el correo y la alerta del panel siguen.
  class StockAlertService
    GRAPH_API_VERSION = "v25.0"
    GRAPH_BASE        = "https://graph.facebook.com"
    NAMES_SHOWN       = 3

    Result = Struct.new(:status, :error, keyword_init: true)

    def self.configured? = ENV["WHATSAPP_ACCESS_TOKEN"].present? && ENV["WHATSAPP_PHONE_NUMBER_ID"].present?

    def initialize(phone:, company_name:, products:)
      @phone = normalize_phone(phone)
      @company_name = company_name
      @products = products
    end

    def call
      return Result.new(status: "simulated") if Demo::Guard.active?
      return Result.new(status: "unavailable") unless self.class.configured?

      deliver
      Result.new(status: "sent")
    rescue => e
      Rails.logger.error("[Whatsapp::StockAlertService] #{e.class}: #{e.message}")
      Result.new(status: "failed", error: e.message.to_s.truncate(200))
    end

    private

    # Los números mexicanos de 10 dígitos llevan la clave de país 52.
    def normalize_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits.length == 10 ? "52#{digits}" : digits
    end

    def names
      shown = @products.first(NAMES_SHOWN).map(&:name).join(", ")
      extra = @products.size - NAMES_SHOWN
      extra.positive? ? "#{shown} (+#{extra})" : shown
    end

    def deliver
      payload = {
        messaging_product: "whatsapp", to: @phone, type: "template",
        template: {
          name: ENV.fetch("WHATSAPP_STOCK_TEMPLATE_NAME", "stock_bajo"),
          language: { code: ENV.fetch("WHATSAPP_STOCK_TEMPLATE_LANG", "es_MX") },
          components: [ { type: "body", parameters: [ @company_name, @products.size.to_s, names ].map { |text| { type: "text", text: text } } } ]
        }
      }
      post("/#{ENV['WHATSAPP_PHONE_NUMBER_ID']}/messages", payload.to_json)
    end

    def post(path, body)
      uri = URI("#{GRAPH_BASE}/#{GRAPH_API_VERSION}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{ENV['WHATSAPP_ACCESS_TOKEN']}"
      request["Content-Type"] = "application/json"
      request.body = body

      response = http.request(request)
      data = JSON.parse(response.body)
      return data if response.is_a?(Net::HTTPSuccess)

      raise data.dig("error", "message") || "WhatsApp API error (HTTP #{response.code})"
    end
  end
end
