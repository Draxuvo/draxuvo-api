module Api
  module V1
    # Canales de la persona autenticada para los avisos de stock bajo en la empresa activa (spec 045, FR-017 y FR-018).
    class NotificationPreferencesController < BaseController
      before_action :require_boss!

      # GET /api/v1/notification_preference
      def show
        render json: payload(NotificationPreference.for(current_user, current_company))
      end

      # PATCH /api/v1/notification_preference { stock_email: false, stock_whatsapp: true }
      def update
        preference = NotificationPreference.for(current_user, current_company)
        preference.stock_email = params[:stock_email] if params.key?(:stock_email)
        preference.stock_whatsapp = params[:stock_whatsapp] if params.key?(:stock_whatsapp)

        unless preference.save
          if preference.errors.of_kind?(:stock_whatsapp, :phone_required)
            raise ApiErrors::UnprocessableEntityError.new(details: [ { code: "phone_required" } ])
          end

          preference.save!
        end
        render json: payload(preference)
      end

      private

      def payload(preference)
        {
          stock_email: preference.stock_email, stock_whatsapp: preference.stock_whatsapp,
          phone_present: current_user.phone.present?, whatsapp_available: Whatsapp::StockAlertService.configured?
        }
      end
    end
  end
end
