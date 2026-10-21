# Tipo de producto (spec 016) con sus reglas y cuántos productos tiene.
class ProductTypeSerializer
  def initialize(type, products_count: nil)
    @type = type
    @products_count = products_count
  end

  def as_json(*)
    unit = @type.default_unit
    {
      id: @type.id, name: @type.name, kind: @type.kind,
      icon: @type.icon, sellable: @type.sellable, counted: @type.counted, fractional: @type.fractional,
      default_unit: unit && { key: unit.key, name: unit.name },
      active: @type.active, position: @type.position,
      products_count: @products_count || @type.products.count
    }
  end
end
