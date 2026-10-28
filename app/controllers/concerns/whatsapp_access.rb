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

  def render_state(status: :ok, extra: {})
    render json: state_json.merge(extra), status: status
  end

  def render_stale_object
    error = ApiErrors::BaseError.new(
      status: :conflict, message: I18n.t("whatsapp_admin.errors.stale_object"),
      details: { code: "stale_object", current: state_json }
    )
    render json: error.as_json, status: :conflict
  end
end
