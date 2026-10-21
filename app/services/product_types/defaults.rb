# Tipos de producto iniciales según el giro de la empresa (spec 016, FR-002) y la regla para clasificar un
# producto que llega sin tipo (FR-015, FR-016). El negocio puede renombrarlos o cambiar sus reglas después.
module ProductTypes
  class Defaults
    DEFINITIONS = {
      "order" => [
        { kind: "sold", name: "Platillo", sellable: true, counted: false, fractional: false, default_unit_key: "pza" },
        { kind: "counted_sold", name: "Bebida", sellable: true, counted: true, fractional: false, default_unit_key: "pza" },
        { kind: "supply", name: "Insumo", sellable: false, counted: true, fractional: true, default_unit_key: "kg" }
      ],
      "service" => [
        { kind: "sold", name: "Servicio", sellable: true, counted: false, fractional: false, default_unit_key: "serv" },
        { kind: "counted_sold", name: "Refacción", sellable: true, counted: true, fractional: false, default_unit_key: "pza" },
        { kind: "supply", name: "Material", sellable: false, counted: true, fractional: true, default_unit_key: "pza" }
      ]
    }.freeze

    # Crea los tipos iniciales que le falten a la empresa (por `kind`, sin duplicar).
    def self.create_missing(company)
      existing = company.product_types.where.not(kind: nil).pluck(:kind)
      DEFINITIONS.fetch(company.order_mode).each_with_index do |definition, index|
        next if existing.include?(definition[:kind])

        name = definition[:name]
        name = "#{name} (#{definition[:kind]})" if company.product_types.where("lower(name) = ?", name.downcase).exists?
        company.product_types.create!(definition.merge(name: name, position: index + 1,
                                                      icon: ProductIcons.default_for(definition[:kind], company.order_mode)))
      end
      company.product_types
    end

    # Tipo para un producto sin tipo (misma regla que la migración): no disponible → insumo; controla inventario →
    # se vende y se cuenta; en servicio, con existencia o mínimo → se vende y se cuenta; lo demás → se vende sin contar.
    def self.classify(company, product)
      create_missing(company)
      kind = if product.available == false then "supply"
      elsif product.tracks_stock then "counted_sold"
      elsif company.order_mode_service? && (product.stock.to_d.positive? || product.min_stock.to_d.positive?) then "counted_sold"
      else "sold"
      end
      company.product_types.find_by(kind: kind) || company.product_types.active.ordered.first
    end
  end
end
