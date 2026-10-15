# Contrato: specs/011-app-movil-hibrida/contracts/api-y-app.md (GET /app_config).
# Público: la app móvil lo consulta al abrir, antes de iniciar sesión.
module Api
  module V1
    class AppConfigController < ApplicationController
      skip_before_action :authenticate_request

      DEFAULT_MIN_VERSION = "0.0.0".freeze

      # GET /api/v1/app_config
      def show
        render json: {
          min_app_version: {
            ios: ENV.fetch("MIN_APP_VERSION_IOS", DEFAULT_MIN_VERSION).presence || DEFAULT_MIN_VERSION,
            android: ENV.fetch("MIN_APP_VERSION_ANDROID", DEFAULT_MIN_VERSION).presence || DEFAULT_MIN_VERSION
          }
        }
      end
    end
  end
end
