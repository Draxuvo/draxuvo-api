module ApiErrors
  class BaseError < StandardError
    attr_reader :status, :message, :details

    def initialize(status: nil, message: nil, details: nil)
      @status  = status || :internal_server_error
      @message = message || I18n.t("errors.default")
      @details = details
    end

    def as_json
      {
        error: {
          status:  Rack::Utils.status_code(status),
          message: message,
          details: details,
        },
      }
    end
  end

  class BadRequestError < BaseError
    def initialize(message: I18n.t("errors.bad_request"), details: nil)
      super(status: :bad_request, message: message, details: details)
    end
  end

  class UnauthorizedError < BaseError
    def initialize(message: I18n.t("errors.unauthorized"), details: nil)
      super(status: :unauthorized, message: message, details: details)
    end
  end

  class ForbiddenError < BaseError
    def initialize(message: I18n.t("errors.forbidden"), details: nil)
      super(status: :forbidden, message: message, details: details)
    end
  end

  class NotFoundError < BaseError
    def initialize(message: I18n.t("errors.not_found"), details: nil)
      super(status: :not_found, message: message, details: details)
    end
  end

  class UnprocessableEntityError < BaseError
    def initialize(message: I18n.t("errors.unprocessable"), details: nil)
      super(status: :unprocessable_entity, message: message, details: details)
    end
  end

  class TooManyRequestsError < BaseError
    def initialize(message: I18n.t("errors.too_many_requests", default: "Demasiadas solicitudes"), details: nil)
      super(status: :too_many_requests, message: message, details: details)
    end
  end
end
