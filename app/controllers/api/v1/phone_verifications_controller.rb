module Api
  module V1
    class PhoneVerificationsController < BaseController
      # POST /api/v1/phone_verifications/send_code
      # Body: { phone: "5219876543210" }
      def send_code
        phone = params.require(:phone)

        ::Whatsapp::OtpService.new(phone).send_code

        render json: { message: "Código enviado al número #{mask_phone(phone)}" }
      rescue ActionController::ParameterMissing
        raise ApiErrors::BadRequestError.new(details: "El parámetro 'phone' es requerido")
      end

      # POST /api/v1/phone_verifications/verify
      # Body: { phone: "5219876543210", code: "483920" }
      def verify
        phone = params.require(:phone)
        code  = params.require(:code)

        result = ::Whatsapp::OtpService.new(phone).verify(code)

        if result[:verified]
          render json: { verified: true, message: "Número verificado correctamente" }
        else
          raise ApiErrors::UnprocessableEntityError.new(details: result[:error])
        end
      rescue ActionController::ParameterMissing => e
        raise ApiErrors::BadRequestError.new(details: "Parámetro requerido faltante: #{e.param}")
      end

      private

      def mask_phone(phone)
        digits = phone.to_s.gsub(/\D/, "")
        "#{digits[0..1]}****#{digits[-4..]}"
      end
    end
  end
end
