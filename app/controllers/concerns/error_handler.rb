module ErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError,                      with: :handle_internal_error
    rescue_from ActiveModel::RangeError, ActiveRecord::RangeError, with: :handle_out_of_range
    rescue_from ActiveRecord::RecordNotFound,       with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid,        with: :handle_unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :handle_bad_request
    rescue_from ApiErrors::BaseError,               with: :handle_api_error
    rescue_from JWT::DecodeError,                   with: :handle_unauthorized
    rescue_from JWT::ExpiredSignature,              with: :handle_unauthorized
  end

  private

  def handle_api_error(error)
    render json: error.as_json, status: error.status
  end

  def handle_bad_request(error)
    handle_api_error(
      ApiErrors::BadRequestError.new(
        message: error.message,
        details: { param: error.param },
      )
    )
  end

  def handle_unauthorized(_error)
    handle_api_error(
      ApiErrors::UnauthorizedError.new(message: I18n.t("auth.invalid_or_expired"))
    )
  end

  def handle_forbidden(_error)
    handle_api_error(
      ApiErrors::ForbiddenError.new(message: I18n.t("auth.not_authorized"))
    )
  end

  def handle_not_found(error)
    handle_api_error(
      ApiErrors::NotFoundError.new(
        message: I18n.t("errors.resource_not_found"),
        details: error.message,
      )
    )
  end

  def handle_unprocessable_entity(error)
    handle_api_error(
      ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("errors.validation_failed"),
        details: error.record.errors.full_messages,
      )
    )
  end

  # Spec 052 (H-32): un número que no cabe en la columna es un dato inválido, no un error del servidor.
  def handle_out_of_range(_error)
    handle_api_error(
      ApiErrors::UnprocessableEntityError.new(message: I18n.t("errors.validation_failed"), details: [ I18n.t("errors.messages.out_of_range") ])
    )
  end

  def handle_internal_error(error)
    Rails.logger.error("#{error.class.name}: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n"))

    handle_api_error(
      ApiErrors::BaseError.new(
        message: I18n.t("errors.internal"),
        details: Rails.env.production? ? nil : error.message,
      )
    )
  end
end
