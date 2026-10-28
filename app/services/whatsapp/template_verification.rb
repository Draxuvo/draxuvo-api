module Whatsapp
  # Verifica con Meta la plantilla de un tipo de mensaje y guarda el resultado (spec 047). Lo usan «Verificar ahora»,
  # el cambio de plantilla y el mensaje de prueba.
  #
  #  - Plantilla aprobada: se guarda y se limpia cualquier aviso anterior.
  #  - Inutilizable (pendiente, rechazada, no encontrada, incompatible): se guarda y, si el tipo estaba encendido, se
  #    apaga solo y se avisa al equipo (una vez por cambio de estado).
  #  - Sin conexión válida, o Meta sin respuesta: no se toca nada (`stale`), se conserva el último estado conocido.
  class TemplateVerification
    Outcome = Struct.new(:type, :stale, keyword_init: true) do
      def stale? = stale == true
    end

    def self.call(type, user: nil) = new(type, user: user).call

    def initialize(type, user: nil)
      @type = type
      @user = user
      @config = Whatsapp::Config.current
    end

    def call
      return outcome(stale: true) unless checkable?

      check = Whatsapp::TemplateCheck.new(
        client: @config.client, waba_id: @config.waba_id, name: @type.template_name,
        language: @type.template_language, expected_variables: Whatsapp::MessageTypes.fetch(@type.kind).expected_variables
      ).call
      Whatsapp::Health.record_failure(@type.kind, check.failure) if check.failure
      return outcome(stale: true) if check.status.nil?

      save(check)
      outcome(stale: false)
    end

    private

    def checkable? = @type.uses_template? && @config.panel? && @config.connection.connected? && @config.access_token.present?

    def outcome(stale:) = Outcome.new(type: @type.reload, stale: stale)

    def save(check)
      @type.update!(template_status: check.status, template_detail: check.detail, template_checked_at: Time.current)
      WhatsappEvent.log!(action: "verified", target: @type.kind, user: @user, result: check.status == "approved" ? "ok" : "failed",
                         data: { status: check.status })

      if check.status == "approved"
        Whatsapp::Health.template_recovered!(@type)
      elsif @type.enabled?
        Whatsapp::Health.template_unusable!(@type.kind, status: check.status, detail: check.detail)
      end
    end
  end
end
