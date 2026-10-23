module Api
  module V1
    # Códigos de barras propios (spec 035): reserva códigos nuevos sin asignarlos (los usa el formulario del producto).
    class BarcodesController < BaseController
      MAX_COUNT = 100

      requires_module :inventory

      def generate
        count = Integer(params[:count].presence || 1, exception: false)
        unless count&.between?(1, MAX_COUNT)
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("labels.errors.invalid_count", count: MAX_COUNT), details: { code: "invalid_count" }
          )
        end

        render json: { codes: Barcodes::Generator.reserve(current_company, count) }
      end
    end
  end
end
