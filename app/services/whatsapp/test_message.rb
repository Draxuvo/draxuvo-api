module Whatsapp
  # Manda un mensaje de prueba de un tipo, por el mismo camino real que los envíos de verdad (spec 047, research R8),
  # con datos que dejan claro que es una prueba: el código es 000000 y el ticket es un texto de prueba.
  #
  # No pasa por los interruptores (se puede probar con el canal apagado), pero sí exige una conexión válida y, si el tipo
  # usa plantilla, que **en ese momento** esté aprobada y sea compatible: antes de mandar se vuelve a consultar a Meta.
  #
  # `status`:
  #   sent         salió bien
  #   simulated    estamos en una demo: no se manda nada
  #   blocked      no se pudo intentar (`reason`: not_connected, connection_error, template_not_approved, template_incompatible)
  #   unreachable  Meta no respondió
  #   failed       Meta lo rechazó (`reason` es una clave de `whatsapp_admin.reasons`, `meta_code` el código)
  class TestMessage
    VERIFICATION_CODE = "000000".freeze

    Result = Struct.new(:status, :reason, :meta_code, :template_status, keyword_init: true) do
      def sent? = status == "sent"
    end

    def self.call(type, phone:, user: nil) = new(type, phone: phone, user: user).call

    def initialize(type, phone:, user: nil)
      @type = type
      @phone = normalize(phone)
      @user = user
    end

    def call
      return Result.new(status: "simulated") if Demo::Guard.active?

      blocked = blocked_result
      return blocked if blocked

      deliver
    end

    private

    def config = @config ||= Whatsapp::Config.current

    def normalize(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits.length == 10 ? "52#{digits}" : digits
    end

    # Antes de mandar se vuelve a consultar la plantilla (FR-010): lo que se prueba es lo que se encendería.
    def blocked_result
      unless config.panel? && config.connection.connected? && config.access_token.present?
        return Result.new(status: "blocked", reason: config.connection.error? ? "connection_error" : "not_connected")
      end
      return nil unless @type.uses_template?

      outcome = Whatsapp::TemplateVerification.call(@type, user: @user)
      return Result.new(status: "blocked", reason: "connection_error") if config.connection.reload.error?
      return Result.new(status: "unreachable") if outcome.stale?

      status = outcome.type.template_status
      return nil if status == "approved"

      Result.new(status: "blocked", reason: status == "incompatible" ? "template_incompatible" : "template_not_approved", template_status: status)
    end

    def deliver
      result = config.client.post("/#{config.phone_number_id}/messages", payload)
      if result.ok?
        Whatsapp::Health.record_success(@type.kind)
        return Result.new(status: "sent")
      end

      failure = result.failure
      Whatsapp::Health.record_failure(@type.kind, failure)
      return Result.new(status: "unreachable") if failure.reason == "meta_unreachable"

      Result.new(status: "failed", reason: failure.reason, meta_code: failure.code)
    end

    def payload
      base = { messaging_product: "whatsapp", to: @phone }
      return base.merge(type: "text", text: { body: I18n.t("whatsapp_admin.test.ticket", locale: locale) }) unless @type.uses_template?

      base.merge(
        type: "template",
        template: {
          name: @type.template_name, language: { code: @type.template_language },
          components: [ { type: "body", parameters: parameters.map { |text| { type: "text", text: text } } } ]
        }
      )
    end

    def parameters
      case @type.kind
      when "verification_code" then [ VERIFICATION_CODE ]
      end
    end

    # El texto de prueba sigue el idioma de la plantilla (es_MX → español, en_US → inglés).
    def locale = @type.template_language.to_s.start_with?("en") ? :en : :es
  end
end
