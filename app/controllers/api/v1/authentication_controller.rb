module Api::V1
  class AuthenticationController < ApplicationController
    rescue_from ApiErrors::BaseError, with: :handle_api_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid

    # En test el cache es null_store; los tests necesitan un store real para el límite.
    RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

    before_action :authenticate_request, only: [ :me ]

    # Spec 052 (H-37): 10 intentos por correo e IP en 15 minutos; el límite no depende de que la contraseña sea correcta.
    # La recuperación de contraseña vive en otro controlador y no se bloquea.
    # Spec 073: el intento bloqueado también queda en la bitácora.
    rate_limit to: ENV.fetch("LOGIN_RATE_LIMIT", 10).to_i, within: ENV.fetch("LOGIN_RATE_WINDOW_MINUTES", 15).to_i.minutes,
               store: RATE_LIMIT_STORE, only: :login,
               by: -> { "login:#{request.remote_ip}:#{params[:email].to_s.downcase}" },
               with: -> {
                 record_attempt("rate_limited", User.find_by(email: params[:email].to_s.strip.downcase))
                 raise ApiErrors::TooManyRequestsError.new(message: I18n.t("auth.too_many_attempts"), details: { retry_after: ENV.fetch("LOGIN_RATE_WINDOW_MINUTES", 15).to_i * 60 })
               }

    # GET /api/v1/auth/me
    def me
      render json: { user: UserSerializer.new(current_user) }, status: :ok
    end

    # POST /api/v1/auth/login
    def login
      validate_login_params

      user = User.find_by(email: params[:email].downcase)

      if user.nil?
        record_attempt("unknown_email")
        raise ApiErrors::NotFoundError.new(details: "No existe una cuenta con este email")
      end

      if user.locked?
        record_attempt("inactive", user)
        raise ApiErrors::ForbiddenError.new(details: "Cuenta inactiva. Contacte al administrador.")
      end

      unless user.authenticate(params[:password])
        record_attempt("wrong_password", user)
        raise ApiErrors::UnauthorizedError.new(details: "Contraseña incorrecta")
      end

      token = jwt_encode(user_id: user.id, email: user.email, full_name: user.full_name)

      record_attempt("success", user)
      render json: { token: token, user: UserSerializer.new(user) }, status: :ok
    end

    private

    def login_params
      params.permit(:email, :password)
    end

    def validate_login_params
      if params[:email].blank? || params[:password].blank?
        record_attempt("invalid") if params[:email].present?
        raise ApiErrors::BadRequestError.new(details: "Email y contraseña son requeridos")
      end

      unless params[:email].match?(URI::MailTo::EMAIL_REGEXP)
        record_attempt("invalid")
        raise ApiErrors::BadRequestError.new(details: "Formato de email inválido")
      end
    end

    # Spec 073: bitácora de inicios de sesión. Nunca recibe la contraseña y nunca hace fallar el login.
    def record_attempt(result, user = nil)
      LoginAttempts::Record.call(request: request, email: params[:email], result: result, user: user)
    end

    def handle_api_error(error)
      render json: error.as_json, status: error.status
    end

    def handle_record_not_found
      render json: ApiErrors::NotFoundError.new(details: "Usuario no encontrado").as_json,
             status: :not_found
    end

    def handle_record_invalid(exception)
      render json: ApiErrors::UnprocessableEntityError.new(details: exception.record.errors.full_messages).as_json,
             status: :unprocessable_entity
    end
  end
end
