require "test_helper"

# Contrato: specs/016-inventario-por-tipo/contracts/api.md (Tipos de producto).
class Api::V1::ProductTypesControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/product_types".freeze

  setup do
    @company = companies(:resto_co)
    @admin = auth_headers(users(:resto_owner), @company)
  end

  test "anyone lists the active types with their rules and product counts; only admins write" do
    get BASE, headers: auth_headers(users(:resto_waiter), @company)
    assert_response :ok
    rows = response.parsed_body["results"]
    assert_equal %w[Platillo Bebida Insumo], rows.map { |t| t["name"] }
    assert_equal({ "sellable" => false, "counted" => true, "fractional" => true }, rows.last.slice("sellable", "counted", "fractional"))
    assert_equal({ "key" => "kg", "name" => "Kilogramo" }, rows.last["default_unit"])
    assert_equal 2, rows.first["products_count"]

    [ users(:resto_waiter), users(:resto_manager) ].each do |user|
      post BASE, params: { product_type: { name: "Postre" } }, headers: auth_headers(user, @company), as: :json
      assert_response :forbidden
    end
  end

  test "an admin creates, renames and changes the rules of a type" do
    post BASE, params: { product_type: { name: "Postre", sellable: true, counted: true, default_unit_key: "pza", position: 4 } },
               headers: @admin, as: :json
    assert_response :created
    id = response.parsed_body["id"]

    patch "#{BASE}/#{product_types(:resto_co_counted).id}", params: { product_type: { name: "Bebidas embotelladas" } }, headers: @admin, as: :json
    assert_response :ok
    assert_equal "Bebidas embotelladas", product_types(:resto_co_counted).reload.name

    patch "#{BASE}/#{id}", params: { product_type: { counted: false } }, headers: @admin, as: :json
    assert_response :ok

    post BASE, params: { product_type: { name: "platillo" } }, headers: @admin, as: :json
    assert_response :unprocessable_entity
  end

  test "turning decimals off with fractional stock answers fractional_stock" do
    @company.products.create!(name: "Camarón", sku: "CAM", product_type: product_types(:resto_co_supply), stock: 2.5)
    patch "#{BASE}/#{product_types(:resto_co_supply).id}", params: { product_type: { fractional: false } }, headers: @admin, as: :json
    assert_response :unprocessable_entity
    assert_equal "fractional_stock", response.parsed_body.dig("error", "details", "code")
    assert_equal [ "Camarón" ], response.parsed_body.dig("error", "details", "products")
  end

  test "a type with products is not deleted but its products can be moved" do
    delete "#{BASE}/#{product_types(:resto_co_sold).id}", headers: @admin
    assert_response :unprocessable_entity
    assert_equal "type_in_use", response.parsed_body.dig("error", "details", "code")

    post "#{BASE}/#{product_types(:resto_co_sold).id}/move_products", params: { to_id: product_types(:resto_co_counted).id }, headers: @admin, as: :json
    assert_response :ok
    assert_equal 2, response.parsed_body["moved"]
    assert products(:resto_sopa).reload.tracks_stock

    delete "#{BASE}/#{product_types(:resto_co_sold).id}", headers: @admin
    assert_response :ok
  end

  test "types of another company are not reachable" do
    patch "#{BASE}/#{product_types(:one_sold).id}", params: { product_type: { name: "Mía" } }, headers: @admin, as: :json
    assert_response :not_found
    post "#{BASE}/#{product_types(:resto_co_sold).id}/move_products", params: { to_id: product_types(:one_counted).id }, headers: @admin, as: :json
    assert_response :unprocessable_entity
  end

  test "an admin sets the suggested icon of a type; a manager cannot; invalid keys are rejected" do
    type = product_types(:resto_co_counted)

    patch "#{BASE}/#{type.id}", params: { product_type: { icon: "beer" } }, headers: @admin, as: :json
    assert_response :ok
    assert_equal "beer", response.parsed_body["icon"]

    patch "#{BASE}/#{type.id}", params: { product_type: { icon: "nope" } }, headers: @admin, as: :json
    assert_response :unprocessable_entity

    patch "#{BASE}/#{type.id}", params: { product_type: { icon: "wine" } },
                                headers: auth_headers(users(:resto_manager), @company), as: :json
    assert_response :forbidden
    assert_equal "beer", type.reload.icon
  end
end
