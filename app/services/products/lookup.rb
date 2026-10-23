module Products
  # Producto de la empresa por código exacto: primero código de barras, luego SKU (spec 034).
  class Lookup
    def self.call(company, code)
      text = Barcodes.normalize(code)
      return nil if text.nil?

      barcode = company.product_barcodes.includes(:product).find_by(code: text)
      barcode&.product || company.products.find_by(sku: text)
    end
  end
end
