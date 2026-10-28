# Contrato: specs/047-configurar-whatsapp/contracts/api.md (PATCH /whatsapp/channel). Interruptor general del canal de
# WhatsApp de toda la plataforma. Apagar nunca se bloquea y conserva las elecciones por tipo; encender exige una conexión
# válida. Siempre `::Whatsapp::` dentro de `Api::V1`, para que el módulo de servicios no quede sombreado.
module Api
  module V1
    module Whatsapp
      class ChannelsController < BaseController
        include WhatsappAccess

        # PATCH /api/v1/whatsapp/channel  { enabled, lock_version }
        def update
          connection = WhatsappConnection.current
          connection.lock_version = params[:lock_version] if params[:lock_version].present?
          enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
          raise ApiErrors::BadRequestError.new(details: { code: "enabled_required" }) if params[:enabled].nil?

          if enabled != connection.enabled?
            ensure_connected!(connection) if enabled
            connection.update!(enabled: enabled)
            WhatsappEvent.log!(action: enabled ? "channel_on" : "channel_off", target: "connection", user: current_user,
                               data: { from: !enabled, to: enabled })
          end
          render_state
        end

        private

        def ensure_connected!(connection)
          return if connection.connected?

          code = connection.error? ? "connection_error" : "not_connected"
          raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("whatsapp_admin.errors.#{code}"), details: { code: code })
        end
      end
    end
  end
end
