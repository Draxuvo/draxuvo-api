# Estado completo de la página de WhatsApp (contrato: specs/047-configurar-whatsapp/contracts/api.md). Nunca incluye la
# llave: solo `token_present` y `token_hint` (últimos 4).
class WhatsappStateSerializer
  def initialize(user:)
    @user = user
    @config = Whatsapp::Config.current
    @connection = @config.connection
  end

  def as_json
    {
      source: @config.source.to_s,
      connection: connection_json,
      message_types: WhatsappMessageType.ensure_all!.map { |type| type_json(type) },
      tests_remaining: Whatsapp::TestLimit.remaining(@user)
    }
  end

  private

  def connection_json
    return env_connection_json if @config.source == :env

    {
      status: @connection.status, enabled: @connection.enabled, managed: @connection.managed,
      phone_number_id: @connection.phone_number_id, waba_id: @connection.waba_id,
      display_phone_number: @connection.display_phone_number, verified_name: @connection.verified_name,
      token_present: @connection.token_present?, token_hint: @connection.token_hint,
      error: error_json, last_verified_at: @connection.last_verified_at, lock_version: @connection.lock_version
    }
  end

  # Solo hay variables de entorno: se muestran sin pista de la llave.
  def env_connection_json
    {
      status: @connection.status, enabled: @connection.enabled, managed: false,
      phone_number_id: @config.phone_number_id, waba_id: nil, display_phone_number: nil, verified_name: nil,
      token_present: true, token_hint: nil, error: nil, last_verified_at: nil, lock_version: @connection.lock_version
    }
  end

  def error_json
    return nil unless @connection.error_message.present? || @connection.error_code.present?

    { code: @connection.error_code, message: @connection.error_message }
  end

  def type_json(type)
    definition = Whatsapp::MessageTypes.fetch(type.kind)
    reason = type.blocked_reason(@connection)
    {
      kind: type.kind, uses_template: type.uses_template?, enabled: type.enabled,
      template_name: type.template_name.presence, template_language: (type.uses_template? ? type.template_language : nil),
      template_status: (type.uses_template? ? type.template_status : nil), template_detail: type.template_detail,
      template_checked_at: type.template_checked_at, expected_variables: definition.expected_variables,
      can_enable: reason.nil?, blocked_reason: reason, lock_version: type.lock_version
    }
  end
end
