module Whatsapp
  # Resolvedor de la configuración de WhatsApp (spec 047): contesta qué llave, qué número, qué plantilla y si un tipo de
  # mensaje está disponible. Es lo único que deben consultar los servicios de envío; ya no leen `ENV` por su cuenta.
  #
  # Quién manda:
  #   :panel  la conexión se usó desde el panel (`managed`); las variables de entorno **se ignoran**, incluso tras
  #           desconectar, para no reactivar unas variables viejas sin avisar.
  #   :env    el panel nunca se usó y hay `WHATSAPP_ACCESS_TOKEN` y `WHATSAPP_PHONE_NUMBER_ID`: comportamiento de siempre.
  #   :none   no hay nada configurado.
  #
  # No guarda nada en caché: cada envío lee el estado vigente, así apagar un tipo o el canal surte efecto de inmediato.
  class Config
    Template = Struct.new(:name, :language)

    # Los nombres de plantilla de las variables de entorno de siempre y sus valores por omisión.
    ENV_TEMPLATES = {
      "verification_code" => [ "WHATSAPP_OTP_TEMPLATE_NAME", "verification_code", "WHATSAPP_OTP_TEMPLATE_LANG" ]
    }.freeze

    def self.current = new

    # Sin crear filas: leer la configuración no escribe en la base.
    def initialize(connection: WhatsappConnection.first)
      @connection = connection || WhatsappConnection.new
    end

    attr_reader :connection

    def source
      return :panel if connection.managed?

      env_credentials? ? :env : :none
    end

    def panel? = source == :panel

    def access_token = panel? ? connection.token : ENV["WHATSAPP_ACCESS_TOKEN"].presence

    def phone_number_id = panel? ? connection.phone_number_id : ENV["WHATSAPP_PHONE_NUMBER_ID"].presence

    def waba_id = panel? ? connection.waba_id : nil

    # La llave guardada ya no se puede leer (p. ej. tras rotar SECRET_KEY_BASE): hay que capturarla otra vez.
    def key_unreadable? = panel? && connection.token_unreadable?

    # Plantilla (nombre e idioma) de un tipo; nil para tickets o si no hay.
    def template_for(kind)
      kind = kind.to_s
      return nil unless Whatsapp::MessageTypes.fetch(kind).uses_template?

      if panel?
        type = message_type(kind)
        type&.template_name.present? ? Template.new(type.template_name, type.template_language) : nil
      else
        name_key, default_name, language_key = ENV_TEMPLATES.fetch(kind)
        Template.new(ENV.fetch(name_key, default_name), ENV.fetch(language_key, "es_MX"))
      end
    end

    # ¿Puede salir ahora un mensaje de este tipo? Panel: conexión válida, interruptor general, interruptor del tipo y
    # plantilla aprobada (si usa plantilla). Variables de entorno: basta con la llave y el número, como hoy.
    def available?(kind)
      kind = kind.to_s
      return false if source == :none
      return true if source == :env

      panel_available?(kind)
    end

    def client(read_timeout: Whatsapp::GraphClient::READ_TIMEOUT)
      Whatsapp::GraphClient.new(token: access_token, read_timeout: read_timeout)
    end

    private

    def env_credentials?
      ENV["WHATSAPP_ACCESS_TOKEN"].present? && ENV["WHATSAPP_PHONE_NUMBER_ID"].present?
    end

    def panel_available?(kind)
      return false unless connection.connected? && connection.enabled? && access_token.present?

      type = message_type(kind)
      return false unless type&.enabled?

      !type.uses_template? || type.template_status == "approved"
    end

    def message_type(kind) = WhatsappMessageType.find_by(kind: kind)
  end
end
