# Movimiento de stock con la cantidad como número y quién lo registró (spec 034).
class StockMovementSerializer
  def initialize(movement)
    @movement = movement
  end

  def as_json(*)
    @movement.as_json.merge(
      "qty" => Product.quantity(@movement.qty),
      "user" => @movement.user && { id: @movement.user.id, name: @movement.user.full_name }
    )
  end
end
