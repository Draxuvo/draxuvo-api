# app/controllers/api/v1/products_controller.rb
module Api
  module V1
    class ProductsController < BaseController
      requires_module :inventory
      before_action :set_product, only: [ :show, :update, :destroy ]

      def index
        products = current_company.products.search(params[:search])
        products = products.where("stock <= min_stock")  if params[:low_stock]  == "true"
        products = products.where(stock: 0)              if params[:out_of_stock] == "true"
        products = products.where(available: true)       if params[:available]  == "true"
        products = products.by_category(params[:category]) if params[:category].present?
        products = apply_sort(products, allowed: %i[name sku stock min_stock unit_cost category created_at], default: :name)
        @pagy, @products = pagy(products)
        render json: paginate_response(@pagy, @products)
      end

      # GET /api/v1/products/menu
      # Retorna los productos disponibles agrupados por categoría para usar como menú
      def menu
        products = current_company.products.available.search(params[:search])
        products = products.by_category(params[:category]) if params[:category].present?
        products = products.order(:category, :name)

        grouped = products.group_by(&:category).map do |cat, items|
          {
            category: cat || I18n.t("products.menu.uncategorized"),
            items: items.map { |p| ProductSerializer.new(p).as_json }
          }
        end

        render json: { menu: grouped }
      end

      def show
        render json: @product
      end

      def create
        product = current_company.products.create!(product_params)
        render json: product, status: :created
      end

      def update
        @product.update!(product_params)
        render json: @product
      end

      def destroy
        @product.destroy!
        render json: { message: I18n.t("products.deleted") }
      end

      # POST /api/v1/products/import
      def import
        raise ApiErrors::BadRequestError.new(message: I18n.t("products.import.file_required")) unless params[:file].present?

        result = Products::ImportService.new(current_company, params[:file]).call

        status = result.errors.any? && result.created.zero? && result.updated.zero? ? :unprocessable_entity : :ok
        render json: {
          message: I18n.t("products.import.completed"),
          created: result.created,
          updated: result.updated,
          errors:  result.errors
        }, status: status
      end

      # GET /api/v1/products/template
      def template
        xlsx = Products::ImportService.generate_template
        send_data xlsx,
                  filename:    I18n.t("products.import.template_filename"),
                  type:        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                  disposition: "attachment"
      end

      private

      def set_product
        @product = current_company.products.find(params[:id])
      end

      def product_params
        params.require(:product).permit(:sku, :name, :description, :category, :price, :available, :stock, :min_stock, :unit_cost)
      end
    end
  end
end
