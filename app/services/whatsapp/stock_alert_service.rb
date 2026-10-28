module Whatsapp
  # Aviso de stock bajo por WhatsApp (spec 045). Lo inicia el negocio, así que fuera de la ventana de 24 h solo
  # sirve un mensaje de plantilla aprobada por Meta. Desde la spec 047 la configuración sale de `Whatsapp::Config`
  # (panel primero, variables de entorno de respaldo). Sin canal disponible no falla: devuelve `unavailable` y el
  # correo y la alerta del panel siguen.
  class StockAlertService
    NAMES_SHOWN = 3

    Result = Struct.new(:status, :error, keyword_init: true)

    # ¿Puede salir ahora un aviso de stock bajo? (conexión válida, interruptores y plantilla aprobada)
    def self.configured? = Whatsapp::Config.current.available?(:stock_alert)

    def initialize(phone:, company_name:, products:)
      @phone = normalize_phone(phone)
      @company_name = company_name
      @products = products
    end

    def call
      return Result.new(status: "simulated") if Demo::Guard.active?
      return Result.new(status: "unavailable") unless config.available?(:stock_alert)

      deliver
    rescue => e
      Rails.logger.error("[Whatsapp::StockAlertService] #{e.class}: #{e.message}")
      Result.new(status: "failed", error: e.message.to_s.truncate(200))
    end

    private

    def config = @config ||= Whatsapp::Config.current

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
      template = config.template_for(:stock_alert)
      payload = {
        messaging_product: "whatsapp", to: @phone, type: "template",
        template: {
          name: template.name,
          language: { code: template.language },
          components: [ { type: "body", parameters: [ @company_name, @products.size.to_s, names ].map { |text| { type: "text", text: text } } } ]
        }
      }

      result = config.client.post("/#{config.phone_number_id}/messages", payload)
      return Result.new(status: "sent") if result.ok?

      Whatsapp::Health.record_failure(:stock_alert, result.failure)
      Result.new(status: "failed", error: result.failure.user_message.truncate(200))
    end
  end
end
