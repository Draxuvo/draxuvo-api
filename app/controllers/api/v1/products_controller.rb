# app/controllers/api/v1/products_controller.rb
module Api
  module V1
    class ProductsController < BaseController
      MAX_GENERATE = 1_000

      requires_module :inventory
      before_action :set_product, only: [ :show, :update, :destroy ]
      before_action :require_icon_permission!, only: [ :create, :update ]

      def index
        products = apply_sort(filtered_products, allowed: %i[name sku stock min_stock unit_cost category created_at], default: :name)
        products = exact_match_first(products) if params[:search].present? && params[:sort_by].blank?
        @pagy, @products = pagy(products)
        availability = ::Restaurant::Availability.new(current_company)
        render json: paginate_response(@pagy, @products.map { |p| ProductSerializer.new(p, availability: availability).as_json })
      end

      # GET /api/v1/products/by_code?code=  (spec 034): código de barras exacto y luego SKU; lo usan las pantallas de captura.
      def by_code
        product = Products::Lookup.call(current_company, params[:code])
        return render json: ProductSerializer.new(product).as_json if product

        raise ApiErrors::NotFoundError.new(message: I18n.t("products.barcodes.not_found"), details: { code: "code_not_found" })
      end

      # GET /api/v1/products/menu
      # Retorna los productos disponibles agrupados por categoría para usar como menú
      def menu
        # Con mesas (modo pedido) el menú es el del restaurante: solo tipos marcados `in_menu` (spec 032).
        sold = current_company.order_mode_order? ? :on_menu : :sellable
        products = current_company.products.available.public_send(sold).includes(:product_type).search(params[:search])
        products = products.by_category(params[:category]) if params[:category].present?
        products = products.order(:category, :name)

        availability = ::Restaurant::Availability.new(current_company)
        grouped = products.group_by(&:category).map do |cat, items|
          {
            category: cat || I18n.t("products.menu.uncategorized"),
            items: items.map { |p| ProductSerializer.new(p, availability: availability).as_json }
          }
        end

        render json: { menu: grouped }
      end

      # Con ProductSerializer: tipo, unidad y existencias como números (spec 016).
      def show
        render json: ProductSerializer.new(@product).as_json
      end

      def create
        product = nil
        Product.transaction do
          ensure_barcodes_free!(nil)
          product = current_company.products.create!(product_params)
          product.replace_barcodes!(barcode_params) unless barcode_params.nil?
        end
        render json: ProductSerializer.new(product.reload).as_json, status: :created
      end

      def update
        Product.transaction do
          ensure_barcodes_free!(@product)
          @product.update!(product_params)
          @product.replace_barcodes!(barcode_params) unless barcode_params.nil?
        end
        render json: ProductSerializer.new(@product.reload).as_json
      end

      def destroy
        @product.destroy!
        render json: { message: I18n.t("products.deleted") }
      end

      # POST /api/v1/products/import
      def import
        file = params[:file]
        raise import_error("file_required", :bad_request) unless file.present?

        ProductImport.fail_stale!
        active = current_company.product_imports.active.first
        if active
          raise ApiErrors::BaseError.new(status: :conflict, message: I18n.t("products.import.in_progress"),
                                         details: { code: "import_in_progress", import: ProductImportSerializer.new(active).as_json })
        end

        filename = file.respond_to?(:original_filename) ? file.original_filename.to_s : File.basename(file.path)
        raise import_error("unsupported_format", :unprocessable_entity) unless %w[.xlsx .xls .csv].include?(File.extname(filename).downcase)
        raise import_error("file_too_large", :unprocessable_entity) if file.size > ProductImport::MAX_BYTES

        total = begin
          Products::ImportService.count_rows(file)
        rescue ApiErrors::BaseError
          raise
        rescue StandardError
          raise import_error("unsupported_format", :unprocessable_entity)
        end
        raise import_error("too_many_rows", :unprocessable_entity) if total > ProductImport::MAX_ROWS

        import = current_company.product_imports.create!(
          user: current_user, filename: filename, total_rows: total, allow_icon: admin?, file_data: File.binread(file.path)
        )
        Products::ImportJob.perform_later(import.id)
        render json: ProductImportSerializer.new(import).as_json, status: :accepted
      end

      # POST /api/v1/products/generate_barcodes  (spec 035): un código propio para cada producto de la selección
      # que no tenga ninguno.
      def generate_barcodes
        ids = Array(params[:product_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
        raise labels_error("empty_selection") if ids.empty?
        raise labels_error("too_many_products", count: MAX_GENERATE) if ids.size > MAX_GENERATE

        products = current_company.products.includes(:barcodes).where(id: ids).order(:id).to_a
        generated = []
        already_had = 0
        products.each_slice(200) do |slice|
          result = Barcodes::Generator.assign(current_company, slice)
          generated.concat(result[:generated])
          already_had += result[:already_had]
        end
        failed = (ids - products.map(&:id)).map { |id| { product_id: id, reason: "not_found" } }
        fresh = current_company.products.includes(:product_type, :barcodes).where(id: generated.map(&:id)).order(:id)
        render json: { generated: generated.size, already_had: already_had, failed: failed,
                       products: fresh.map { |product| ProductSerializer.new(product).as_json } }
      end

      # GET /api/v1/products/export  (spec 034): el inventario en Excel con los filtros del listado.
      def export
        xlsx = Products::ExportService.new(filtered_products).call
        send_data xlsx,
                  filename:    I18n.t("products.export.filename"),
                  type:        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                  disposition: "attachment"
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

      # Los filtros del listado, compartidos con la exportación a Excel.
      def filtered_products
        products = current_company.products.includes(:product_type, :barcodes).search(params[:search])
        # Bajo inventario y agotado solo en tipos que se cuentan (spec 016, FR-013).
        products = products.low_stock                                   if params[:low_stock]  == "true"
        products = products.counted.where(stock: 0)                     if params[:out_of_stock] == "true"
        products = products.where(available: true)                      if params[:available]  == "true"
        products = products.sellable                                    if params[:sellable] == "true"
        products = products.where(product_type_id: params[:product_type_id]) if params[:product_type_id].present?
        products = products.by_category(params[:category]) if params[:category].present?
        products
      end

      # La coincidencia exacta de código de barras o SKU va primero (spec 034, FR-004).
      def exact_match_first(products)
        term = params[:search].to_s.strip
        order = Product.sanitize_sql_array([
          "(products.sku = ? OR EXISTS (SELECT 1 FROM product_barcodes pbx WHERE pbx.product_id = products.id AND pbx.code = ?)) DESC, products.name ASC",
          term, term
        ])
        products.reorder(Arel.sql(order))
      end

      # Lista completa de códigos del formulario (reemplaza a la anterior); nil si no se mandó.
      def barcode_params
        return @barcode_params if defined?(@barcode_params)

        raw = params[:barcodes]
        raw = params[:product][:barcodes] if raw.nil? && params[:product].respond_to?(:key?)
        @barcode_params = raw.nil? ? nil : Products::Barcodes.clean_list(Array(raw))
      end

      def ensure_barcodes_free!(product)
        return if barcode_params.nil?

        code, other = Products::Barcodes.conflicts(current_company, barcode_params, product).first
        return unless other

        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("products.barcodes.taken", barcode: code, product: other.name),
          details: { code: "barcode_taken", barcode: code, product: { id: other.id, name: other.name } }
        )
      end

      def labels_error(code, **options)
        ApiErrors::UnprocessableEntityError.new(message: I18n.t("labels.errors.#{code}", **options), details: { code: code })
      end

      def import_error(code, status)
        ApiErrors::BaseError.new(status: status, message: I18n.t("products.import.#{code}"), details: { code: code })
      end

      def set_product
        @product = current_company.products.find(params[:id])
      end

      def admin?
        Authorizable::ADMIN_ROLES.include?(current_role)
      end

      # El icono lo cambian solo administrador y dueño; el encargado edita el resto del producto (spec 026).
      def require_icon_permission!
        attrs = params[:product]
        return unless attrs.respond_to?(:key?) && attrs.key?(:icon)
        return if admin?
        return if attrs[:icon].presence == @product&.icon

        forbid!
      end

      def product_params
        permitted = %i[sku name description category price available stock min_stock unit_cost station_id product_type_id unit_key]
        permitted << :icon if admin?
        params.require(:product).permit(*permitted)
      end
    end
  end
end
