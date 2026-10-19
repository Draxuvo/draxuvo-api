# app/serializers/product_serializer.rb
class ProductSerializer
  # `availability` (Restaurant::Availability) se comparte entre productos para no repetir la consulta.
  def initialize(product, availability: nil)
    @product = product
    @availability = availability || Restaurant::Availability.new(product.company)
  end

  def as_json(*)
    {
      id:          @product.id,
      sku:         @product.sku,
      name:        @product.name,
      description: @product.description,
      category:    @product.category,
      price:       @product.price,
      available:   @product.available,
      stock:       @product.stock,
      min_stock:   @product.min_stock,
      unit_cost:   @product.unit_cost,
      low_stock:   @product.min_stock.present? && @product.stock <= @product.min_stock,
      tracks_stock: @product.tracks_stock,
      station_id:  @product.station_id,
      available_qty: @availability.available_qty(@product),
      sold_out:    @availability.sold_out?(@product),
      low:         @availability.low?(@product)
    }
  end
end
