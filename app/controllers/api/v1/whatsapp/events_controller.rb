# Contrato: specs/047-configurar-whatsapp/contracts/api.md (GET /whatsapp/events). Historial de la configuración de
# WhatsApp: quién cambió qué y cuándo, el más reciente primero. Solo super admin. Los eventos nunca guardan secretos y los
# teléfonos ya están enmascarados al registrarlos.
module Api
  module V1
    module Whatsapp
      class EventsController < BaseController
        include WhatsappAccess

        # GET /api/v1/whatsapp/events
        def index
          @pagy, events = pagy(WhatsappEvent.includes(:user).recent)
          render json: paginate_response(@pagy, events.map { |event| serialize(event) })
        end

        private

        def serialize(event)
          {
            id: event.id, action: event.action, target: event.target, result: event.result,
            user: event.user && { id: event.user.id, name: event.user.full_name },
            data: event.data, meta_code: event.meta_code, created_at: event.created_at
          }
        end
      end
    end
  end
end
