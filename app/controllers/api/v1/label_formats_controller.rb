module Api
  module V1
    # Formatos de etiqueta (spec 035): los comunes del catálogo (solo lectura) y los propios de la empresa.
    class LabelFormatsController < BaseController
      PERMITTED = %i[name kind page_width_mm page_height_mm columns rows label_width_mm label_height_mm
                     margin_top_mm margin_left_mm gap_x_mm gap_y_mm].freeze

      requires_module :inventory
      before_action :set_format, only: %i[update destroy]

      def index
        formats = Labels::Catalog.all + current_company.label_formats.order(:name).to_a
        render json: { results: formats.map { |format| LabelFormatSerializer.new(format).as_json } }
      end

      def create
        format = current_company.label_formats.new(format_params)
        save!(format)
        render json: LabelFormatSerializer.new(format).as_json, status: :created
      end

      def update
        @format.assign_attributes(format_params)
        save!(@format)
        render json: LabelFormatSerializer.new(@format).as_json
      end

      def destroy
        @format.destroy!
        head :no_content
      end

      private

      # Un formato común (`std:…`) o de otra empresa no existe para quien edita: 404.
      def set_format
        @format = current_company.label_formats.find(params[:id])
      end

      def format_params
        raw = params.fetch(:label_format, params)
        raw.permit(*PERMITTED)
      end

      def save!(format)
        return if format.save

        errors = format.errors
        code = if errors.of_kind?(:name, :taken) then "name_taken"
        elsif errors.of_kind?(:base, :formats_limit) then "formats_limit"
        else "invalid_dimensions"
        end
        message = code == "invalid_dimensions" ? errors.full_messages.to_sentence : I18n.t("labels.errors.#{code}", count: LabelFormat::MAX_PER_COMPANY)
        raise ApiErrors::UnprocessableEntityError.new(message: message, details: { code: code, errors: errors.to_hash })
      end
    end
  end
end
