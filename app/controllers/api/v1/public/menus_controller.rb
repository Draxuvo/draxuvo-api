# Contrato: specs/059-menu-qr-mesas/contracts/api.md (GET /public/menus/:token).
# Menú de una mesa para el comensal que escanea el QR: público y de solo lectura. Excepción documentada a los
# Principios II y III (spec 059, Assumptions; plan.md, Complexity Tracking): sin JWT, sin X-Company-Id y sin la puerta
# de suscripción normal. La empresa sale solo del token y Restaurant::PublicMenu reaplica módulo, suscripción,
# sucursal y demo. Lo pide el navegador del comensal directo (no el servidor de `web`), así que la IP es la real.
module Api
  module V1
    module Public
      class MenusController < BaseController
        # En test el cache es null_store; el límite necesita un store real.
        RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

        skip_before_action :authenticate_request, :check_subscription!, :enter_demo_context
        before_action :throttle_by_ip

        # GET /api/v1/public/menus/:token
        def show
          response.headers["Cache-Control"] = "no-store"
          use_request_host_for_storage!
          result = ::Restaurant::PublicMenu.call(params[:token])

          case result.status
          when :invalid
            raise ApiErrors::NotFoundError.new(message: I18n.t("public_menu.errors.menu_link_invalid"),
                                               details: { code: "menu_link_invalid" })
          when :unavailable
            raise ApiErrors::ForbiddenError.new(message: I18n.t("public_menu.errors.menu_unavailable"),
                                                details: { code: "menu_unavailable" })
          else
            render json: PublicMenuSerializer.new(result).as_json
          end
        end

        private

        # El límite se lee en cada petición (no al cargar la clase) para poder ajustarlo sin reiniciar y en pruebas.
        def throttle_by_ip
          limit = ENV.fetch("PUBLIC_MENU_RATE_LIMIT", 120).to_i
          count = RATE_LIMIT_STORE.increment("public_menu:#{request.remote_ip}", 1, expires_in: 1.minute)
          return unless count && count > limit

          raise ApiErrors::TooManyRequestsError
        end
      end
    end
  end
end
