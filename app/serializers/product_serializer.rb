# app/serializers/product_serializer.rb
class ProductSerializer
  def initialize(product)
    @product = product
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
      low_stock:   @product.min_stock.present? && @product.stock <= @product.min_stock
    }
  end
end
