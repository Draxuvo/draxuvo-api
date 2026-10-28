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
    end
  end
end
