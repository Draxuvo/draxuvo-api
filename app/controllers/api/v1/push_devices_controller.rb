module Api
  module V1
    # Teléfonos de la persona autenticada para los avisos push (spec 057, FR-002 y FR-003). El dispositivo es de la
    # persona, no de la empresa: `X-Company-Id` se exige (Principio II) y valida la membresía, pero no se guarda.
    # Excepción a la puerta de suscripción (FR-005a): con la empresa suspendida, vencida o cancelada se puede registrar y,
    # sobre todo, dar de baja un teléfono.
    class PushDevicesController < BaseController
      skip_before_action :check_subscription!
      before_action { current_company }

      # POST /api/v1/push_devices { token, platform, locale, app_version }
      def create
        unprocessable!("invalid_token") unless PushDevice.valid_token?(params[:token])
        unprocessable!("invalid_platform") unless PushDevice::PLATFORMS.include?(params[:platform].to_s)

        device = PushDevice.register!(user: current_user, token: params[:token], platform: params[:platform],
                                      locale: params[:locale], app_version: params[:app_version])
        render json: device
      end

      # DELETE /api/v1/push_devices/:token — siempre 204; un token ajeno o inexistente no se toca.
      def destroy
        current_user.push_devices.where(token: params[:token].to_s).delete_all
        head :no_content
      end

      private

      def unprocessable!(code)
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("push.errors.#{code}"), details: { code: code })
      end
    end
  end
end
