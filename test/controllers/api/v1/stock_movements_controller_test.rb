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

  test "a movement keeps who registered it and the list returns the user (spec 034)" do
    move(@shrimp, "entry", "2")
    assert_response :created
    assert_equal users(:resto_owner).id, StockMovement.order(:id).last.user_id
    assert_equal users(:resto_owner).id, response.parsed_body.dig("movement", "user", "id")

    get "/api/v1/products/#{@shrimp.id}/stock_movements", headers: @headers
    assert_equal users(:resto_owner).full_name, response.parsed_body["results"].first.dig("user", "name")
  end

  # --- Spec 054 (H-54): entrada y salida son cantidades positivas ---

  test "an entry or exit with a zero or negative quantity answers 422 and leaves the stock" do
    %w[entry exit].each do |type|
      [ -2, 0 ].each do |qty|
        move(@shrimp, type, qty)
        assert_response :unprocessable_entity, "#{type} #{qty}"
      end
    end
    assert_equal 10, @shrimp.reload.stock
    assert_equal 0, @shrimp.stock_movements.where(initial: false).count
  end
end
