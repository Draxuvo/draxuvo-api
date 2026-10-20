module Api
  module V1
    # Tipos de producto de la empresa (spec 016): los ve cualquiera con sesión; los administra el admin o el dueño.
    # Son pocos por empresa, así que no se paginan.
    class ProductTypesController < BaseController
      before_action :require_admin!, only: %i[create update destroy move_products]
      before_action :set_type, only: %i[update destroy move_products]

      def index
        types = current_company.product_types.ordered
        types = types.active unless admin? && ActiveModel::Type::Boolean.new.cast(params[:include_inactive])
        counts = current_company.products.group(:product_type_id).count
        render json: { results: types.map { |type| ProductTypeSerializer.new(type, products_count: counts.fetch(type.id, 0)).as_json } }
      end

      def create
        type = current_company.product_types.create!(type_params)
        render json: ProductTypeSerializer.new(type).as_json, status: :created
      end

      def update
        @type.assign_attributes(type_params)
        if !@type.save && @type.errors.added?(:fractional, :fractional_stock)
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("product_types.fractional_stock"),
            details: { code: "fractional_stock", products: @type.products_with_fractions }
          )
        end
        @type.save!
        render json: ProductTypeSerializer.new(@type).as_json
      end

      # Con productos no se borra: se desactiva o se mueven sus productos (FR-003).
      def destroy
        unless @type.destroy
          raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("product_types.in_use"), details: { code: "type_in_use" })
        end

        render json: ProductTypeSerializer.new(@type, products_count: 0).as_json
      end

      # POST /product_types/:id/move_products { to_id }: pasa todos sus productos a otro tipo activo.
      def move_products
        target = current_company.product_types.active.where.not(id: @type.id).find_by(id: params[:to_id])
        unless target
          raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("product_types.invalid_target"), details: { code: "invalid_target" })
        end

        moved = 0
        Product.transaction do
          @type.products.find_each do |product|
            product.update!(product_type: target)
            moved += 1
          end
        end
        render json: { moved: moved }
      end

      private

      def admin?
        Authorizable::ADMIN_ROLES.include?(current_role)
      end

      def set_type
        @type = current_company.product_types.find(params[:id])
      end

      def type_params
        params.require(:product_type).permit(:name, :sellable, :counted, :fractional, :default_unit_key, :active, :position)
      end
    end
  end
end
