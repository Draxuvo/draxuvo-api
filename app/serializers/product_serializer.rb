# app/serializers/product_serializer.rb
class ProductSerializer
  # `availability` (Restaurant::Availability) se comparte entre productos para no repetir la consulta.
  # `photo: true` agrega la foto del menú QR (spec 061); solo el detalle del producto la pide, el resto del panel no la
  # muestra (FR-021) y así no firma URLs en las listas.
  def initialize(product, availability: nil, photo: false)
    @product = product
    @availability = availability || Restaurant::Availability.new(product.company)
    @photo = photo
  end

  def as_json(*)
    json = attributes
    json[:photo] = @product.photo_payload(public: false) if @photo
    json
  end

  private

  def attributes
    type = @product.product_type
    counted = type&.counted
    unit = @product.unit
    {
      id:          @product.id,
      sku:         @product.sku,
      barcodes:    @product.barcode_codes,
      name:        @product.name,
      description: @product.description,
      icon:        @product.icon,
      category:    @product.category,
      price:       @product.price,
      available:   @product.available,
      # En tipos que no se cuentan la existencia no aplica (spec 016).
      stock:       counted ? Product.quantity(@product.stock) : nil,
      min_stock:   counted ? Product.quantity(@product.min_stock) : nil,
      unit_cost:   @product.unit_cost,
      low_stock:   @product.low_stock?,
      product_type: type && { id: type.id, name: type.name, sellable: type.sellable, counted: type.counted, fractional: type.fractional, icon: type.icon },
      unit:        unit && { key: unit.key, name: unit.name },
      tracks_stock: @product.tracks_stock,
      station_id:  @product.station_id,
      available_qty: @availability.available_qty(@product),
      sold_out:    @availability.sold_out?(@product),
      low:         @availability.low?(@product)
    }
  end
end
