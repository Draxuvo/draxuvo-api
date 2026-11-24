# Contrato: specs/073-bitacora-accesos-estado/contracts/api.md. Bitácora de inicios de sesión de toda la plataforma: solo
# el super admin, sin cabecera de empresa.
module Api
  module V1
    class LoginAttemptsController < BaseController
      DEFAULT_PAGE_SIZE = 50
      MAX_PAGE_SIZE = 100

      before_action :require_super_admin!

      # GET /api/v1/login_attempts
      def index
        validate_filters!
        scope = LoginAttempt.filtered(filter_params).recent.includes(user: { user_companies: :company })
        @pagy, attempts = pagy(scope, limit: page_size)
        render json: paginate_response(@pagy, attempts.map { |attempt| LoginAttemptSerializer.new(attempt).as_json })
      end

      # GET /api/v1/login_attempts/summary
      def summary
        render json: LoginAttempts::Summary.call
      end

      private

      def filter_params
        params.permit(:q, :company_id, :ip, :channel, :since, :from, :to, result: [])
      end

      def page_size
        (params[:page_size].presence || DEFAULT_PAGE_SIZE).to_i.clamp(1, MAX_PAGE_SIZE)
      end

      def validate_filters!
        if params[:ip].present?
          begin
            IPAddr.new(params[:ip].to_s)
          rescue IPAddr::Error
            unprocessable!("invalid_ip")
          end
        end

        from = parse_date(:from)
        to = parse_date(:to)
        unprocessable!("invalid_range") if from && to && from > to
      end

      def parse_date(key)
        return nil if params[key].blank?

        Date.iso8601(params[key].to_s)
      rescue Date::Error
        unprocessable!("invalid_range")
      end

      def unprocessable!(code)
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("login_attempts.#{code}"), details: { code: code })
      end
    end
  end
end
