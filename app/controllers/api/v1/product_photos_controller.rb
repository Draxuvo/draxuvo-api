module Api
  module V1
    # Foto del producto para el menú QR (spec 061, contracts/api.md). Solo dueño, administrador y super admin, con el
    # módulo de restaurante: la foto solo se ve en el menú de las mesas. La foto viaja aparte del formulario del
    # producto (multipart, con avance y cancelación en el panel) y no toca ningún otro dato del producto (FR-008).
    class ProductPhotosController < BaseController
      requires_module :inventory
      requires_module :restaurant
      before_action :require_boss!
      before_action :set_product
      before_action :use_request_host_for_storage!

      # PUT /api/v1/products/:product_id/photo (multipart: file, style) — sube o reemplaza.
      # PATCH /api/v1/products/:product_id/photo { style } — cambia solo el estilo, sin volver a subir la foto.
      def update
        if request.put?
          unprocessable!("photo_missing", "missing") if params[:file].blank?
          style = params[:style].presence
          invalid_style! if style && !Product::PHOTO_STYLES.include?(style.to_s)
          save_photo { @product.attach_photo!(params[:file], style: style, user: current_user) }
        else
          not_found! unless @product.photo.attached?
          invalid_style! unless Product::PHOTO_STYLES.include?(params[:style].to_s)
          @product.update_photo_style!(params[:style], user: current_user)
        end
        render_product
      end

      # DELETE /api/v1/products/:product_id/photo
      def destroy
        not_found! unless @product.photo.attached?
        @product.remove_photo!
        render_product
      end

      private

      def set_product
        @product = current_company.products.find(params[:product_id])
      end

      def render_product
        render json: ProductSerializer.new(@product.reload, photo: true).as_json
      end

      # Tipo y tamaño los valida el modelo por el contenido del archivo; el error lleva su código (contracts/api.md).
      def save_photo
        yield
      rescue ActiveRecord::RecordInvalid => e
        detail = e.record.errors.details[:photo]&.first&.dig(:error)
        case detail
        when :too_large then unprocessable!("photo_too_large", "too_large")
        when :invalid_type then unprocessable!("photo_invalid_type", "invalid_type")
        else raise
        end
      end

      def invalid_style!
        unprocessable!("invalid_photo_style", "invalid_style")
      end

      def not_found!
        raise ApiErrors::NotFoundError.new(message: I18n.t("products.photo.not_found"), details: { code: "photo_not_found" })
      end

      def unprocessable!(code, message_key)
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("products.photo.#{message_key}"), details: { code: code })
      end
    end
  end
end
