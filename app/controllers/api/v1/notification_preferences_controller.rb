module Api
  module V1
    # Canal de correo de la persona autenticada para los avisos de stock bajo en la empresa activa (spec 045, FR-017 y
    # FR-018). Desde la spec 048 es el único canal externo: `stock_whatsapp` ya no se lee, no se escribe ni se devuelve
    # (si un cliente antiguo lo manda, se ignora sin error).
    class NotificationPreferencesController < BaseController
      before_action :require_boss!

      # GET /api/v1/notification_preference
      def show
        render json: payload(NotificationPreference.for(current_user, current_company))
      end

      # PATCH /api/v1/notification_preference { stock_email: false }
      def update
        preference = NotificationPreference.for(current_user, current_company)
        preference.stock_email = params[:stock_email] if params.key?(:stock_email)
        preference.save!
        render json: payload(preference)
      end

      private

      def payload(preference)
        { stock_email: preference.stock_email }
      end
    end
  end
end
