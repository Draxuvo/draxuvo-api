# Contrato: specs/047-configurar-whatsapp/contracts/api.md. Estado de la configuración de WhatsApp de la plataforma
# (solo super admin, sin X-Company-Id).
module Api
  module V1
    class WhatsappController < BaseController
      include WhatsappAccess

      # GET /api/v1/whatsapp
      def show
        render_state
      end

      # GET /api/v1/whatsapp/guide — el texto exacto para crear cada plantilla en Meta (solo los tipos con plantilla).
      def guide
        render json: { results: ::Whatsapp::MessageTypes.with_template.map(&:guide) }
      end
    end
  end
end
