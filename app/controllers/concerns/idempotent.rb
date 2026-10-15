# Hace idempotentes las acciones indicadas cuando la petición trae `Idempotency-Key`.
# Sin cabecera, la acción corre igual que siempre. Solo se guardan respuestas 2xx.
#
#   include Idempotent
#   idempotent :create_note, :create_photo
module Idempotent
  extend ActiveSupport::Concern

  class_methods do
    def idempotent(*actions)
      around_action :with_idempotency, only: actions
    end
  end

  private

  def with_idempotency(&block)
    key = request.headers["Idempotency-Key"].presence
    return yield if key.nil?

    if key.length > IdempotencyKey::MAX_KEY_LENGTH
      raise ApiErrors::BadRequestError.new(details: I18n.t("errors.idempotency.key_too_long"))
    end

    IdempotencyKey.transaction do
      # Serializa dos envíos simultáneos con la misma llave para que no se duplique el efecto.
      IdempotencyKey.connection.execute(
        "SELECT pg_advisory_xact_lock(#{current_user.id.to_i}, hashtext(#{IdempotencyKey.connection.quote(key)}))"
      )
      stored = IdempotencyKey.find_by(user_id: current_user.id, key: key)
      stored ? replay_idempotent(stored) : run_and_store_idempotent(key, &block)
    end
  end

  def replay_idempotent(stored)
    route = "#{request.request_method} #{request.path}"
    if "#{stored.request_method} #{stored.request_path}" != route
      raise ApiErrors::UnprocessableEntityError.new(details: I18n.t("errors.idempotency.key_reused"))
    end

    render body: stored.response_body, content_type: "application/json", status: stored.response_status
  end

  def run_and_store_idempotent(key)
    yield
    return unless performed? && response.successful?

    IdempotencyKey.create!(
      user: current_user, key: key, request_method: request.request_method, request_path: request.path,
      response_status: response.status, response_body: response.body
    )
  end
end
