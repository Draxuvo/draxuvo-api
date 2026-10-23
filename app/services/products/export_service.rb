module Products
  # Inventario en Excel con las mismas columnas de la plantilla de importación, para corregirlo y reimportarlo (spec 034).
  class ExportService
    TEXT_KEYS = %w[sku barcodes].freeze

    def initialize(products)
      @products = products
    end

    def call
      package = Axlsx::Package.new
      workbook = package.workbook
      workbook.styles do |styles|
        header = styles.add_style bg_color: "1F4E79", fg_color: "FFFFFF", b: true, sz: 11, alignment: { horizontal: :center }
        workbook.add_worksheet(name: I18n.t("products.import.template_sheet")) do |sheet|
          sheet.add_row ImportService::HEADER_KEYS.map { |key| I18n.t("products.import.headers.#{key}") }, style: header
          types = ImportService::HEADER_KEYS.map { |key| TEXT_KEYS.include?(key) ? :string : nil }
          @products.includes(:product_type, :barcodes).find_each(batch_size: 500) { |product| sheet.add_row(row(product), types: types) }
          sheet.column_widths 15, 30, 35, 20, 12, 12, 10, 12, 12, 16, 12, 12, 28
        end
      end
      package.to_stream.read
    end

    private

    def row(product)
      counted = product.counted?
      ImportService::HEADER_KEYS.map do |key|
        case key
        when "stock" then counted ? Product.quantity(product.stock) : nil
        when "min_stock" then Product.quantity(product.min_stock)
        when "available" then product.available ? "TRUE" : "FALSE"
        when "product_type" then product.product_type&.name
        when "unit" then product.unit_key.presence
        when "barcodes" then product.barcode_codes.join("; ").presence
        else product.public_send(key)
        end
      end
    end
  end
end
