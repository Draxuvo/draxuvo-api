# Conteo físico con sus renglones: lo contado contra el stock del sistema (spec 034).
class StockCountSerializer
  def initialize(count, items: true)
    @count = count
    @items = items
  end

  def as_json(*)
    json = {
      id: @count.id,
      name: @count.name,
      status: @count.status,
      user: person(@count.user),
      created_at: @count.created_at,
      confirmed_at: @count.confirmed_at,
      items_count: @count.items.size
    }
    json[:items] = items_json if @items
    json
  end

  private

  def items_json
    availability = Restaurant::Availability.new(@count.company)
    @count.items.sort_by(&:id).map do |item|
      current = item.product.stock.to_d
      {
        product: ProductSerializer.new(item.product, availability: availability).as_json,
        counted_qty: Product.quantity(item.counted_qty),
        baseline_stock: Product.quantity(item.baseline_stock),
        current_stock: Product.quantity(current),
        difference: Product.quantity(item.counted_qty.to_d - current),
        changed: current != item.baseline_stock.to_d
      }
    end
  end

  def person(user)
    user && { id: user.id, name: user.full_name }
  end
end
