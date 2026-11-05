module Push
  # Texto y datos de un aviso push (spec 057, contracts/push-message.md). Título «<empresa> · <tipo>» y una línea corta
  # en el idioma del dispositivo. Nunca lleva montos, datos de pago ni datos personales de clientes (FR-016): quien arma
  # el cuerpo solo pasa mesa o nombre del pedido para llevar, número y título de la orden, o nombres de productos.
  class Message
    TITLE_MAX = 60

    attr_reader :kind, :company, :path, :subject_id, :body_key, :body_args

    def initialize(kind:, company:, path:, subject_id:, body_key:, body_args: {})
      @kind = kind.to_s
      @company = company
      @path = path
      @subject_id = subject_id
      @body_key = body_key
      @body_args = body_args
    end

    def title(locale) = "#{company.name} · #{I18n.t("push.kinds.#{kind}", locale: locale)}"

    # Un valor de `body_args` puede ser un `Proc` que recibe el idioma (p. ej. la etiqueta de una alerta ya traducida).
    def body(locale)
      args = body_args.transform_values { |value| value.respond_to?(:call) ? value.call(locale) : value }
      I18n.t("push.bodies.#{body_key}", **args, locale: locale)
    end

    def for_device(device)
      definition = Kinds.fetch(kind)
      {
        to: device.token, title: title(device.locale), body: body(device.locale),
        data: { kind: kind, company_id: company.id, path: path, subject_id: subject_id },
        channelId: definition.channel, priority: definition.priority, sound: "default", ttl: definition.ttl
      }
    end

    def self.truncate(text, max = TITLE_MAX) = text.to_s.squish.truncate(max)
  end
end
