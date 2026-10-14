# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (POST /registrations).
# Público: el prospecto se registra desde draxuvo-web y entra con su prueba gratuita activa.
module Api
  module V1
    class RegistrationsController < ApplicationController
      # En test el cache es null_store; los tests necesitan un store real para el límite (R7).
      RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

      skip_before_action :authenticate_request

      rate_limit to: 5, within: 1.hour, store: RATE_LIMIT_STORE, only: :create,
                 with: -> { raise ApiErrors::TooManyRequestsError }

      # POST /api/v1/registrations
      def create
        result = Registrations::CreateService.new(registration_params).call

        Email::WelcomeService.new(
          result.user,
          company_name: result.company.name,
          trial_ends_at: result.subscription.trial_ends_at
        ).call

        token = JwtHelper.jwt_encode(user_id: result.user.id, email: result.user.email, full_name: result.user.full_name)
        render json: { token: token, user: UserSerializer.new(result.user.reload) }, status: :created
      end

      private

      def registration_params
        params.require(:registration).permit(
          :first_name, :last_name, :phone, :email, :password, :company_name, :plan, :billing_cycle
        )
      end
    end
  end
end
