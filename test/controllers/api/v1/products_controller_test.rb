require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md (GET /products, filtro out_of_stock).
class Api::V1::ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    create_product("AGO-1", stock: 0, min_stock: 2)
    create_product("AGO-2", stock: 0, min_stock: nil)
    create_product("BAJ-1", stock: 3, min_stock: 5)
    create_product("OK-1", stock: 10, min_stock: 5)
  end

  test "out_of_stock=true returns only products with stock 0" do
    get "/api/v1/products", params: { out_of_stock: "true" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "total")
    assert_equal %w[AGO-1 AGO-2], skus
  end

  test "out_of_stock combines with low_stock using AND" do
    get "/api/v1/products", params: { out_of_stock: "true", low_stock: "true" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal %w[AGO-1], skus
  end

  test "an out_of_stock value other than true is ignored" do
    [ "false", "yes", "1", "" ].each do |value|
      get "/api/v1/products", params: { out_of_stock: value }, headers: auth_headers(@owner, @company)

      assert_response :ok, "out_of_stock=#{value.inspect} should not fail"
      assert_equal 4, response.parsed_body.dig("info", "total"), "out_of_stock=#{value.inspect} should not filter"
    end
  end

  test "another company's products are not listed" do
    companies(:enterprise_co).products.create!(name: "Ajeno", sku: "AGO-X", stock: 0, min_stock: 1)

    get "/api/v1/products", params: { out_of_stock: "true" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_not_includes skus, "AGO-X"
  end

  private

  def create_product(sku, stock:, min_stock:)
    @company.products.create!(name: "Producto #{sku}", sku: sku, stock: stock, min_stock: min_stock)
  end

  def skus
    response.parsed_body["results"].map { |p| p["sku"] }.sort
  end

  # Restaurante (spec 013, FR-034, FR-040, FR-041).
  test "menu marks tracked products sold out or low using what open checks already committed" do
    company = companies(:resto_co)
    get "/api/v1/products/menu", headers: auth_headers(users(:resto_owner), company)

    assert_response :ok
    items = response.parsed_body["menu"].flat_map { |group| group["items"] }.index_by { |i| i["sku"] }
    tacos = items.fetch("TAC-001") # 10 en inventario, 1 comprometido en la cuenta abierta
    assert_equal true, tacos["tracks_stock"]
    assert_equal 9, tacos["available_qty"]
    assert_equal false, tacos["sold_out"]
    assert_equal true, items.fetch("COL-001")["low"]
    assert_nil items.fetch("SOP-001")["available_qty"]
    assert_equal false, items.fetch("SOP-001")["sold_out"]
  end

  test "a product can be assigned a station and inventory tracking" do
    company = companies(:resto_co)
    product = products(:resto_agua)

    patch "/api/v1/products/#{product.id}", params: { product: { station_id: stations(:bar).id, tracks_stock: true } },
                                            headers: auth_headers(users(:resto_owner), company), as: :json

    assert_response :ok
    assert_equal stations(:bar), product.reload.station
    assert product.tracks_stock?
  end

  test "a station from another company is rejected" do
    foreign = Station.create!(company: companies(:pro_co), name: "Ajena")

    patch "/api/v1/products/#{products(:resto_agua).id}", params: { product: { station_id: foreign.id } },
                                                          headers: auth_headers(users(:resto_owner), companies(:resto_co)), as: :json

    assert_response :unprocessable_entity
  end
end
