# Contrato: specs/073-bitacora-accesos-estado/contracts/api.md. Estado de toda la plataforma: solo el super admin, sin
# cabecera de empresa. Responde 200 aunque falle un tercero: cada tarjeta trae su propio estado.
module Api
  module V1
    class SystemStatusController < BaseController
      before_action :require_super_admin!

      # GET /api/v1/system_status
      # `refresh=1` lo manda el botón «Actualizar»: lo interno siempre se lee de nuevo y lo externo respeta su copia de
      # 1 minuto, así que no cambia la lectura.
      def show
        render json: Monitoring::SystemStatus.call
      end
    end
  end
end
