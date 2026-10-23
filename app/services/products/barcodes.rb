module Products
  # Códigos de barras como texto exacto (spec 034). Excel entrega las celdas numéricas como Integer o Float.
  module Barcodes
    SEPARATOR = /[;,\n]/

    module_function

    def normalize(value)
      text = case value
      when Integer then value.to_s
      when Float then value == value.to_i ? value.to_i.to_s : value.to_s
      when BigDecimal then value == value.to_i ? value.to_i.to_s : value.to_s("F")
      else value.to_s
      end
      text.strip.presence
    end

    # Una celda con varios códigos separados por `;`, `,` o saltos de línea.
    def split(cell)
      return [] if cell.nil?
      return [ normalize(cell) ].compact unless cell.is_a?(String)

      cell.split(SEPARATOR).filter_map { |part| normalize(part) }
    end

    # Lista sin vacíos ni repetidos, en el orden recibido.
    def clean_list(values)
      Array(values).filter_map { |value| normalize(value) }.uniq
    end

    # Códigos de `codes` que ya pertenecen a otro producto de la empresa: [[code, producto]].
    def conflicts(company, codes, product = nil)
      scope = ProductBarcode.where(company_id: company.id, code: clean_list(codes)).includes(:product)
      scope = scope.where.not(product_id: product.id) if product&.persisted?
      scope.map { |barcode| [ barcode.code, barcode.product ] }
    end
  end
end
