module Api
  module V1
    # Logo propio de la empresa (spec 063, contracts/api.md). Solo dueño, administrador y super admin de la empresa de
    # `X-Company-Id`; el super admin usa el mismo endpoint con el id de la empresa que atiende (como la hoja «Módulos»).
    class CompanyLogosController < BaseController
      before_action :require_boss!
      before_action :use_request_host_for_storage!

      # PUT /api/v1/company/logo (multipart: file) — sube o reemplaza.
      def update
        unprocessable!("logo_missing", "missing") if params[:file].blank?
        current_company.attach_logo!(params[:file], user: current_user)
        render_logo
      rescue ActiveRecord::RecordInvalid => e
        case e.record.errors.details[:logo]&.first&.dig(:error)
        when :too_large then unprocessable!("logo_too_large", "too_large")
        when :invalid_type then unprocessable!("logo_invalid_type", "invalid_type")
        else raise
        end
      end

      # DELETE /api/v1/company/logo
      def destroy
        unless current_company.logo.attached?
          raise ApiErrors::NotFoundError.new(message: I18n.t("companies.logo.not_found"), details: { code: "logo_not_found" })
        end

        current_company.remove_logo!(user: current_user)
        render json: { logo: nil }
      end

      private

      def render_logo
        render json: { logo: current_company.reload.logo_payload }
      end

      def unprocessable!(code, message_key)
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("companies.logo.#{message_key}"), details: { code: code })
      end
    end
  end
end
