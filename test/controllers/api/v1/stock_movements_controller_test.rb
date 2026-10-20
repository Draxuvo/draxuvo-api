require "test_helper"

# Movimientos con decimales solo en tipos que los admiten (spec 016, FR-010).
class Api::V1::StockMovementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @headers = auth_headers(users(:resto_owner), @company)
    @shrimp = @company.products.create!(name: "Camarón", sku: "CAM", product_type: product_types(:resto_co_supply), stock: 10)
  end

  def move(product, type, qty)
    post "/api/v1/products/#{product.id}/stock_movements", params: { movement_type: type, qty: qty,
                                                                   stock_movement: { movement_type: type, qty: qty } },
                                    headers: @headers, as: :json
  end

  test "a fractional exit leaves 7.5 kg and answers numbers" do
    move(@shrimp, "exit", "2.5")
    assert_response :created
    assert_equal BigDecimal("7.5"), @shrimp.reload.stock
    assert_equal 7.5, response.parsed_body.dig("product", "stock")
    assert_equal 2.5, response.parsed_body.dig("movement", "qty")
    assert_equal({ "key" => "kg", "name" => "Kilogramo" }, response.parsed_body.dig("product", "unit"))
  end

  test "a whole-only type rejects fractions" do
    move(products(:resto_cola), "entry", "1.5")
    assert_response :unprocessable_entity
    assert_equal 2, products(:resto_cola).reload.stock
  end
end
