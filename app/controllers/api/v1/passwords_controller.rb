# app/controllers/api/v1/passwords_controller.rb
module Api::V1
  class PasswordsController < ApplicationController
    skip_before_action :authenticate_request, only: [ :reset, :update_with_token ]
    before_action :set_user_from_token, only: [ :update_with_token ]

    # PATCH /api/v1/passwords/update
    # Update password for authenticated user
    def update
      validate_password_update_params

      unless current_user.authenticate(params[:current_password])
        raise ApiErrors::UnauthorizedError.new(details: "Contraseña actual incorrecta")
      end

      if current_user.update(password: params[:new_password])
        render json: {
          message: "Contraseña actualizada exitosamente",
          user: UserSerializer.new(current_user)
        }, status: :ok
      else
        raise ApiErrors::UnprocessableEntityError.new(details: current_user.errors.full_messages)
      end
    end

    # POST /api/v1/passwords/reset
    # Send password reset email
    def reset
      validate_reset_params

      user = User.find_by(email: params[:email].downcase)

      if user.nil?
        raise ApiErrors::NotFoundError.new(details: "No existe una cuenta con este email")
      end

      if user.locked?
        raise ApiErrors::ForbiddenError.new(details: "Cuenta inactiva. Contacte al administrador.")
      end

      result = Email::PasswordResetService.new(user).call

      if result[:success]
        render json: {
          message: "Se ha enviado un correo con las instrucciones para restablecer tu contraseña"
        }, status: :ok
      else
        raise ApiErrors::UnprocessableEntityError.new(details: result[:error])
      end
    end

    # PATCH /api/v1/passwords/update_with_token
    # Update password using reset token
    def update_with_token
      validate_token_update_params

      ActiveRecord::Base.transaction do
        @user.update!(password: params[:new_password], active: true)
        @user.employee&.update!(status: :active)
      end

      render json: {
        message: "Contraseña restablecida exitosamente",
        user: UserSerializer.new(@user)
      }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      raise ApiErrors::UnprocessableEntityError.new(details: e.record.errors.full_messages)
    end

    private

    def validate_password_update_params
      required_params = [ :current_password, :new_password, :new_password_confirmation ]
      missing_params = required_params.select { |param| params[param].blank? }

      unless missing_params.empty?
        raise ApiErrors::BadRequestError.new(
          details: "Los siguientes campos son requeridos: #{missing_params.join(", ")}",
        )
      end

      unless params[:new_password] == params[:new_password_confirmation]
        raise ApiErrors::BadRequestError.new(details: "La confirmación de contraseña no coincide")
      end

      if params[:new_password].length < 6
        raise ApiErrors::BadRequestError.new(details: "La nueva contraseña debe tener al menos 6 caracteres")
      end
    end

    def validate_reset_params
      if params[:email].blank?
        raise ApiErrors::BadRequestError.new(details: "El email es requerido")
      end

      unless params[:email].match?(URI::MailTo::EMAIL_REGEXP)
        raise ApiErrors::BadRequestError.new(details: "Formato de email inválido")
      end
    end

    def validate_token_update_params
      required_params = [ :new_password, :new_password_confirmation ]
      missing_params = required_params.select { |param| params[param].blank? }

      unless missing_params.empty?
        raise ApiErrors::BadRequestError.new(
          details: "Los siguientes campos son requeridos: #{missing_params.join(", ")}",
        )
      end

      unless params[:new_password] == params[:new_password_confirmation]
        raise ApiErrors::BadRequestError.new(details: "La confirmación de contraseña no coincide")
      end

      if params[:new_password].length < 6
        raise ApiErrors::BadRequestError.new(details: "La nueva contraseña debe tener al menos 6 caracteres")
      end
    end

    def set_user_from_token
      token = params[:token]

      if token.blank?
        raise ApiErrors::BadRequestError.new(details: "Token es requerido")
      end

      begin
        decoded = jwt_decode(token)
        @user = User.find(decoded[:user_id])

        # Verify token hasn't expired
        if decoded[:exp] && Time.at(decoded[:exp]) < Time.current
          raise ApiErrors::UnauthorizedError.new(details: "El token ha expirado")
        end
      rescue ActiveRecord::RecordNotFound
        raise ApiErrors::UnauthorizedError.new(details: "Token inválido")
      rescue JWT::DecodeError, JWT::ExpiredSignature
        raise ApiErrors::UnauthorizedError.new(details: "Token inválido o expirado")
      rescue => e
        raise ApiErrors::UnauthorizedError.new(details: "Error al validar token")
      end
    end

    def jwt_decode(token)
      JwtHelper.jwt_decode(token)
    end
  end
end
