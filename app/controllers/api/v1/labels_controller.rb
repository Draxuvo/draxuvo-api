module Api
  module V1
    # Etiquetas autoadhesivas (spec 035): resumen con avisos y PDF con el tamaño exacto del papel.
    class LabelsController < BaseController
      requires_module :inventory

      def check
        render json: service.check
      rescue Labels::PdfService::Invalid => e
        raise_invalid(e)
      end

      def pdf
        send_data service.call, type: "application/pdf", filename: "etiquetas.pdf", disposition: "attachment"
      rescue Labels::PdfService::Invalid => e
        raise_invalid(e)
      end

      private

      def service
        Labels::PdfService.new(
          company: current_company, format: resolve_format, items: items_params,
          show_name: params.fetch(:show_name, true), show_price: params.fetch(:show_price, false),
          start_position: params[:start_position]
        )
      end

      # `std:<clave>` del catálogo o el id de un formato propio de la empresa.
      def resolve_format
        id = params[:format_id].to_s
        format = id.start_with?(Labels::Catalog::PREFIX) ? Labels::Catalog.find(id) : current_company.label_formats.find_by(id: id.to_i)
        format || raise_invalid(Labels::PdfService::Invalid.new(:invalid_format))
      end

      def items_params
        Array(params[:items]).map do |item|
          { product_id: item[:product_id], copies: item[:copies] || 1, code: item[:code] }
        end
      end

      def raise_invalid(error)
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("labels.errors.#{error.code}", **error.options),
          details: { code: error.code.to_s }.merge(error.details)
        )
      end
    end
  end
end
