require "test_helper"

class Api::V1::StockCountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @waiter = auth_headers(users(:resto_waiter), @company)
    @owner = auth_headers(users(:resto_owner), @company)
    @tacos = products(:resto_tacos)
    @cola = products(:resto_cola)
  end

  def create_count(headers = @waiter, **params)
    post "/api/v1/stock_counts", params: params, headers: headers, as: :json
    response.parsed_body["id"]
  end

  def scan(id, params, headers: @waiter)
    post "/api/v1/stock_counts/#{id}/scan", params: params, headers: headers, as: :json
  end

  test "any member creates a draft and lists it by status" do
    id = create_count(name: "Pasillo 3")
    assert_response :created
    assert_equal [ "Pasillo 3", "draft", users(:resto_waiter).id ], response.parsed_body.values_at("name", "status") + [ response.parsed_body.dig("user", "id") ]

    get "/api/v1/stock_counts", params: { status: "draft" }, headers: @owner
    assert_equal [ id ], response.parsed_body["results"].map { |c| c["id"] }
    assert_equal 0, response.parsed_body["results"].first["items_count"]
    assert_not response.parsed_body["results"].first.key?("items")

    get "/api/v1/stock_counts", params: { status: "confirmed" }, headers: @owner
    assert_empty response.parsed_body["results"]
  end

  test "scan sums one by default by barcode or sku and shows the difference against the system" do
    id = create_count
    scan(id, { code: "7502000000002" })
    scan(id, { code: "TAC-001", qty: 2 })

    assert_response :ok
    item = response.parsed_body["items"].first
    assert_equal [ 3, @tacos.stock.to_i, 3 - @tacos.stock.to_i, false ], item.values_at("counted_qty", "baseline_stock", "difference", "changed")
    assert_equal "TAC-001", item.dig("product", "sku")
  end

  test "scan by product_id, unknown code and products that are not counted" do
    id = create_count
    scan(id, { product_id: @cola.id })
    assert_response :ok

    scan(id, { code: "000" })
    assert_response :not_found
    assert_equal "code_not_found", response.parsed_body.dig("error", "details", "code")

    scan(id, { product_id: products(:resto_sopa).id })
    assert_response :unprocessable_entity
    assert_equal "not_counted", response.parsed_body.dig("error", "details", "code")

    scan(id, { product_id: @tacos.id, qty: 1.5 })
    assert_equal "invalid_qty", response.parsed_body.dig("error", "details", "code")
  end

  test "scans from two people on the same product add up into one row instead of overwriting each other" do
    id = create_count
    scan(id, { code: "TAC-001" })
    scan(id, { code: "TAC-001" }, headers: @owner)

    assert_equal 2, response.parsed_body["items"].first["counted_qty"]
    assert_equal 1, StockCountItem.where(stock_count_id: id).count
  end

  test "set and remove an item" do
    id = create_count
    scan(id, { code: "TAC-001" })

    patch "/api/v1/stock_counts/#{id}/items/#{@tacos.id}", params: { counted_qty: 9 }, headers: @waiter, as: :json
    assert_response :ok
    assert_equal 9, response.parsed_body["items"].first["counted_qty"]

    patch "/api/v1/stock_counts/#{id}/items/#{@tacos.id}", params: { counted_qty: -1 }, headers: @waiter, as: :json
    assert_response :unprocessable_entity

    delete "/api/v1/stock_counts/#{id}/items/#{@tacos.id}", headers: @waiter, as: :json
    assert_response :ok
    assert_empty response.parsed_body["items"]
  end

  test "confirming adjusts against the current stock, flags what changed and is idempotent" do
    id = create_count
    scan(id, { code: "TAC-001", qty: 40 })
    StockMovement.create!(product: @tacos, company: @company, movement_type: :entry, qty: 1, note: "entró algo")
    @tacos.increment!(:stock, 1)

    get "/api/v1/stock_counts/#{id}", headers: @waiter
    assert_equal true, response.parsed_body["items"].first["changed"]

    post "/api/v1/stock_counts/#{id}/confirm", headers: @owner, as: :json
    assert_response :ok
    assert_equal 40, @tacos.reload.stock
    body = response.parsed_body
    assert_equal "confirmed", body.dig("count", "status")
    assert_equal [ @tacos.id ], body["changed_since_baseline"]
    assert_equal users(:resto_owner).id, body["adjustments"].first.dig("user", "id")

    assert_no_difference -> { StockMovement.count } do
      post "/api/v1/stock_counts/#{id}/confirm", headers: @owner, as: :json
    end
    assert_equal body["adjustments"].map { |a| a["id"] }, response.parsed_body["adjustments"].map { |a| a["id"] }
  end

  test "a closed count rejects scans and changes" do
    id = create_count
    scan(id, { code: "TAC-001" })
    post "/api/v1/stock_counts/#{id}/confirm", headers: @owner, as: :json

    scan(id, { code: "TAC-001" })
    assert_response :unprocessable_entity
    assert_equal "count_closed", response.parsed_body.dig("error", "details", "code")

    delete "/api/v1/stock_counts/#{id}", headers: @owner
    assert_response :unprocessable_entity
  end

  test "discarding leaves the stock as it was and closes the draft" do
    id = create_count
    scan(id, { code: "TAC-001", qty: 99 })
    before = @tacos.reload.stock

    delete "/api/v1/stock_counts/#{id}", headers: @waiter
    assert_response :no_content
    assert_equal before, @tacos.reload.stock
    assert_equal "discarded", StockCount.find(id).status

    scan(id, { code: "TAC-001" })
    assert_response :unprocessable_entity
  end

  test "counts are scoped to the company" do
    id = create_count
    other = auth_headers(users(:pro_co_owner), companies(:pro_co))

    get "/api/v1/stock_counts/#{id}", headers: other
    assert_response :not_found
    get "/api/v1/stock_counts", headers: other
    assert_empty response.parsed_body["results"]
  end

  test "a company with the inventory module turned off is refused" do
    @company.update!(disabled_modules: [ "inventory" ])

    get "/api/v1/stock_counts", headers: @owner

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end
end
