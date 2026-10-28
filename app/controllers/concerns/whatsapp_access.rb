# Acceso a la configuración de WhatsApp (spec 047): solo el super admin, sin cabecera de empresa. Las ediciones usan
# bloqueo optimista; si otra persona cambió lo mismo, se responde 409 con el estado vigente para que la UI lo muestre.
module WhatsappAccess
  extend ActiveSupport::Concern

  included do
    before_action :require_super_admin!
    rescue_from ActiveRecord::StaleObjectError, with: :render_stale_object
  end

  private

  def state_json
    WhatsappStateSerializer.new(user: current_user).as_json
  end

  # `stale_kind`: el tipo cuya verificación no pudo hacerse (Meta sin respuesta); se marca con `stale: true` y conserva
  # el último estado conocido.
  def render_state(status: :ok, stale_kind: nil)
    state = state_json
    if stale_kind
      state[:message_types] = state[:message_types].map { |type| type[:kind] == stale_kind ? type.merge(stale: true) : type }
    end
    render json: state, status: status
  end

  def render_stale_object
    error = ApiErrors::BaseError.new(
      status: :conflict, message: I18n.t("whatsapp_admin.errors.stale_object"),
      details: { code: "stale_object", current: state_json }
    )
    render json: error.as_json, status: :conflict
  end
end
