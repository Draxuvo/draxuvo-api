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

  # --- spec 016 ---

  test "the menu, the sellable filter and the type filter respect the product type" do
    company = companies(:resto_co)
    headers = auth_headers(users(:resto_owner), company)
    company.products.create!(name: "Limón", sku: "LIM", product_type: product_types(:resto_co_supply), stock: 3)

    get "/api/v1/products/menu", headers: headers
    names = response.parsed_body["menu"].flat_map { |group| group["items"].map { |item| item["name"] } }
    assert_not_includes names, "Limón"
    assert_includes names, "Sopa del día"

    get "/api/v1/products", params: { sellable: "true" }, headers: headers
    assert_not_includes response.parsed_body["results"].map { |p| p["sku"] }, "LIM"

    get "/api/v1/products", params: { product_type_id: product_types(:resto_co_supply).id }, headers: headers
    assert_equal [ "LIM" ], response.parsed_body["results"].map { |p| p["sku"] }
  end

  test "a product of a type that is not counted has no stock in the response" do
    get "/api/v1/products/#{products(:resto_sopa).id}", headers: auth_headers(users(:resto_owner), companies(:resto_co))
    body = response.parsed_body
    assert_nil body["stock"]
    assert_equal false, body["low_stock"]
    assert_equal "Platillo", body.dig("product_type", "name")
  end

  def create_product(sku, stock:, min_stock:)
    # Un tipo que se cuenta (spec 016): solo esos tienen existencia, agotado y bajo inventario.
    counted = ProductTypes::Defaults.create_missing(@company).find_by!(kind: "counted_sold")
    @company.products.create!(name: "Producto #{sku}", sku: sku, stock: stock, min_stock: min_stock, product_type: counted)
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

  test "a product can be assigned a station and a counted type, which turns on inventory tracking" do
    company = companies(:resto_co)
    product = products(:resto_agua)

    patch "/api/v1/products/#{product.id}", params: { product: { station_id: stations(:bar).id, product_type_id: product_types(:resto_co_counted).id } },
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

  # --- spec 026: iconos ---

  test "admins and owners set, change and clear a product icon" do
    resto = companies(:resto_co)
    product = products(:resto_tacos)
    owner = auth_headers(users(:resto_owner), resto)

    patch "/api/v1/products/#{product.id}", params: { product: { icon: "taco" } }, headers: owner, as: :json
    assert_response :ok
    assert_equal "taco", response.parsed_body["icon"]
    assert_equal "taco", product.reload.icon

    patch "/api/v1/products/#{product.id}", params: { product: { icon: "" } }, headers: owner, as: :json
    assert_response :ok
    assert_nil response.parsed_body["icon"]
  end

  test "a waiter cannot change the icon but still edits the other fields" do
    resto = companies(:resto_co)
    product = products(:resto_tacos)
    product.update!(icon: "taco")
    staff_h = auth_headers(users(:resto_waiter), resto)

    patch "/api/v1/products/#{product.id}", params: { product: { icon: "pizza" } }, headers: staff_h, as: :json
    assert_response :forbidden
    assert_equal "taco", product.reload.icon

    patch "/api/v1/products/#{product.id}", params: { product: { description: "Con piña" } }, headers: staff_h, as: :json
    assert_response :ok
    assert_equal "Con piña", product.reload.description

    patch "/api/v1/products/#{product.id}", params: { product: { icon: "taco", description: "Sin piña" } }, headers: staff_h, as: :json
    assert_response :ok
    assert_equal "taco", product.reload.icon
  end

  test "a waiter cannot create a product with an icon, an admin can" do
    resto = companies(:resto_co)
    type = product_types(:resto_co_sold)
    post "/api/v1/products", params: { product: { sku: "M-1", name: "Mole", product_type_id: type.id, icon: "soup" } },
                             headers: auth_headers(users(:resto_waiter), resto), as: :json
    assert_response :forbidden

    post "/api/v1/products", params: { product: { sku: "M-1", name: "Mole", product_type_id: type.id, icon: "soup" } },
                             headers: auth_headers(users(:resto_owner), resto), as: :json
    assert_response :created
    assert_equal "soup", response.parsed_body["icon"]
  end

  test "an icon outside the catalog is rejected" do
    patch "/api/v1/products/#{products(:resto_tacos).id}", params: { product: { icon: "nope" } },
                                                           headers: auth_headers(users(:resto_owner), companies(:resto_co)), as: :json
    assert_response :unprocessable_entity
  end

  test "the list, the menu and the detail return the product icon and the type icon" do
    resto = companies(:resto_co)
    headers = auth_headers(users(:resto_waiter), resto)
    products(:resto_tacos).update!(icon: "taco")
    products(:resto_tacos).product_type.update!(icon: "utensils")
    products(:resto_sopa).product_type.update!(icon: "utensils")

    get "/api/v1/products/menu", headers: headers
    item = response.parsed_body["menu"].flat_map { |g| g["items"] }.find { |i| i["name"] == products(:resto_tacos).name }
    assert_equal "taco", item["icon"]
    assert_equal "utensils", item.dig("product_type", "icon")

    get "/api/v1/products/#{products(:resto_sopa).id}", headers: headers
    assert_nil response.parsed_body["icon"]
    assert_equal "utensils", response.parsed_body.dig("product_type", "icon")
  end

  # --- spec 032 ---

  test "in an order-mode company the menu leaves out the types that are not on the menu" do
    company = companies(:resto_co)
    headers = auth_headers(users(:resto_owner), company)
    abarrotes = company.product_types.create!(name: "Abarrotes", kind: "sold", sellable: true, in_menu: false, position: 9)
    company.products.create!(name: "Arroz a granel", sku: "ARR", product_type: abarrotes, price: 20)

    get "/api/v1/products/menu", headers: headers
    names = response.parsed_body["menu"].flat_map { |group| group["items"].map { |item| item["name"] } }
    assert_not_includes names, "Arroz a granel"
    assert_includes names, "Sopa del día"

    get "/api/v1/products", params: { sellable: "true" }, headers: headers
    assert_includes response.parsed_body["results"].map { |p| p["sku"] }, "ARR"
  end

  test "in a service company the menu keeps every sellable type even if it is not on the menu" do
    company = companies(:pro_co)
    type = company.product_types.create!(name: "Mano de obra", kind: "sold", sellable: true, in_menu: false, position: 9)
    company.products.create!(name: "Revisión", sku: "REV", product_type: type, price: 100)

    get "/api/v1/products/menu", headers: auth_headers(users(:pro_co_owner), company)
    names = response.parsed_body["menu"].flat_map { |group| group["items"].map { |item| item["name"] } }
    assert_includes names, "Revisión"
  end

  # --- spec 034: códigos de barras ---

  def resto_headers = auth_headers(users(:resto_owner), companies(:resto_co))

  test "creates a product with barcodes and returns them in order" do
    post "/api/v1/products", params: { product: { sku: "PAP-1", name: "Cuaderno", price: 30, barcodes: [ "7509990000011", " 7509990000028 ", "7509990000011", "" ] } },
                             headers: resto_headers, as: :json

    assert_response :created
    assert_equal %w[7509990000011 7509990000028], response.parsed_body["barcodes"]
  end

  test "update replaces the barcodes and omitting them changes nothing" do
    tacos = products(:resto_tacos)
    patch "/api/v1/products/#{tacos.id}", params: { product: { name: "Tacos pastor" } }, headers: resto_headers, as: :json
    assert_equal [ "7502000000002" ], response.parsed_body["barcodes"]

    patch "/api/v1/products/#{tacos.id}", params: { product: { barcodes: [ "7503000000003", "7503000000010" ] } }, headers: resto_headers, as: :json
    assert_response :ok
    assert_equal %w[7503000000003 7503000000010], response.parsed_body["barcodes"]
    assert_nil ProductBarcode.find_by(code: "7502000000002")

    patch "/api/v1/products/#{tacos.id}", params: { product: { barcodes: [] } }, headers: resto_headers, as: :json
    assert_equal [], response.parsed_body["barcodes"]
  end

  test "a code that belongs to another product of the company answers barcode_taken with its name" do
    sopa = products(:resto_sopa)
    patch "/api/v1/products/#{sopa.id}", params: { product: { barcodes: [ "7502000000002" ] } }, headers: resto_headers, as: :json

    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "barcode_taken", details["code"]
    assert_equal "Tacos al pastor", details.dig("product", "name")
    assert_equal [], sopa.reload.barcode_codes
  end

  test "the same code in another company does not conflict" do
    other = companies(:pro_co)
    post "/api/v1/products", params: { product: { sku: "X-1", name: "Otro negocio", barcodes: [ "7502000000002" ] } },
                             headers: auth_headers(@owner, other), as: :json
    assert_response :created
  end

  test "search finds a product by any of its barcodes, partial or exact, and the exact match goes first" do
    resto_headers
    company = companies(:resto_co)
    exact = company.products.create!(name: "Aaa primero por nombre", sku: "AAA", product_type: product_types(:resto_co_sold))
    exact.replace_barcodes!([ "7502000000002X" ])

    get "/api/v1/products", params: { search: "7502000000002" }, headers: resto_headers
    assert_equal [ "TAC-001", "AAA" ], response.parsed_body["results"].map { |p| p["sku"] }

    get "/api/v1/products", params: { search: "000000002" }, headers: resto_headers
    assert_includes response.parsed_body["results"].map { |p| p["sku"] }, "TAC-001"
  end

  test "by_code finds by barcode or sku and answers 404 code_not_found otherwise" do
    get "/api/v1/products/by_code", params: { code: "7502000000002" }, headers: resto_headers
    assert_response :ok
    assert_equal "TAC-001", response.parsed_body["sku"]

    get "/api/v1/products/by_code", params: { code: "TAC-001" }, headers: resto_headers
    assert_response :ok

    get "/api/v1/products/by_code", params: { code: "000" }, headers: resto_headers
    assert_response :not_found
    assert_equal "code_not_found", response.parsed_body.dig("error", "details", "code")

    get "/api/v1/products/by_code", params: { code: "7502000000002" }, headers: auth_headers(@owner, companies(:pro_co))
    assert_response :not_found
  end

  # --- spec 035: códigos propios en lote ---

  def generate_for(ids, headers: resto_headers)
    post "/api/v1/products/generate_barcodes", params: { product_ids: ids }, headers: headers, as: :json
  end

  test "generate_barcodes gives a code only to the selected products that have none and summarizes" do
    tacos = products(:resto_tacos)
    sopa = products(:resto_sopa)
    cola = products(:resto_cola)

    generate_for([ tacos.id, sopa.id, cola.id, 0 ])

    assert_response :ok
    body = response.parsed_body
    assert_equal [ 2, 1, [ { "product_id" => 0, "reason" => "not_found" } ] ], [ body["generated"], body["already_had"], body["failed"] ]
    assert_equal [ sopa.id, cola.id ].sort, body["products"].map { |p| p["id"] }.sort
    assert_equal [ "7502000000002" ], tacos.reload.barcode_codes
    body["products"].each { |p| assert_match(/\A29\d{11}\z/, p["barcodes"].first) }
  end

  test "generate_barcodes never touches products of another company" do
    other = products(:two)

    generate_for([ other.id ])

    assert_equal 0, response.parsed_body["generated"]
    assert_equal [ { "product_id" => other.id, "reason" => "not_found" } ], response.parsed_body["failed"]
    assert_empty other.reload.barcode_codes
  end

  test "generate_barcodes rejects an empty selection and more than 1,000 products" do
    generate_for([])
    assert_response :unprocessable_entity
    assert_equal "empty_selection", response.parsed_body.dig("error", "details", "code")

    generate_for((1..1001).to_a)
    assert_response :unprocessable_entity
    assert_equal "too_many_products", response.parsed_body.dig("error", "details", "code")
  end

  test "generate_barcodes works for any member with the inventory module" do
    generate_for([ products(:resto_sopa).id ], headers: auth_headers(users(:resto_waiter), companies(:resto_co)))

    assert_response :ok
    assert_equal 1, response.parsed_body["generated"]
  end
end
