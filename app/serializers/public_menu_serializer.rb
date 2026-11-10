# Menú público de una mesa (spec 059). Lista blanca exacta de specs/059-menu-qr-mesas/contracts/api.md: nada de ids,
# SKU, códigos, costos, existencias, tipos, estaciones, cuentas ni personas (FR-013). Si hace falta un campo nuevo,
# se agrega aquí a propósito y en la prueba de claves del controlador.
class PublicMenuSerializer
  def initialize(result)
    @result = result
  end

  def as_json(*)
    {
      business: { name: @result.company.name },
      table: { name: @result.table.name },
      categories: @result.categories.map do |category|
        { name: category.name, items: category.items.map { |item| item_json(item) } }
      end
    }
  end

  private

  def item_json(item)
    product = item.product
    {
      name: product.name,
      description: product.description.presence,
      # Montos en centavos MXN (constitution); `products.price` es decimal(10,2).
      price_cents: (product.price.to_d * 100).round.to_i,
      # Ya resuelto como en el panel (spec 026): el del producto, si no el de su tipo.
      icon: product.icon.presence || product.product_type&.icon.presence,
      sold_out: item.sold_out
    }
  end
end
