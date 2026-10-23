require "test_helper"

class Api::V1::StockReceiptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @tacos = products(:resto_tacos)
    @waiter = auth_headers(users(:resto_waiter), @company)
  end

  def receive(items, headers: @waiter, **extra)
    post "/api/v1/stock_receipts", params: { items: items, **extra }, headers: headers, as: :json
  end

  test "any member records a receipt, answering the movements and the updated products" do
    before = @tacos.stock
    receive([ { product_id: @tacos.id, qty: 6 } ], note: "Factura 7")

    assert_response :created
    body = response.parsed_body
    assert_equal [ "entry", 6, "Factura 7", users(:resto_waiter).id ], [ body["movements"][0]["movement_type"], body["movements"][0]["qty"], body["movements"][0]["note"], body["movements"][0]["user"]["id"] ]
    assert_equal before.to_i + 6, body["products"][0]["stock"]
    assert_equal before + 6, @tacos.reload.stock
  end

  test "a retry with the same Idempotency-Key does not duplicate the entries" do
    headers = @waiter.merge("Idempotency-Key" => "recibo-1")
    before = @tacos.stock

    receive([ { product_id: @tacos.id, qty: 6 } ], headers: headers)
    assert_response :created
    first = response.body

    assert_no_difference -> { StockMovement.count } do
      receive([ { product_id: @tacos.id, qty: 6 } ], headers: headers)
    end
    assert_response :created
    assert_equal first, response.body
    assert_equal before + 6, @tacos.reload.stock
  end

  test "answers 422 with the code and the product for a type that is not counted" do
    receive([ { product_id: @tacos.id, qty: 1 }, { product_id: products(:resto_sopa).id, qty: 1 } ])

    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "not_counted", details["code"]
    assert_equal "Sopa del día", details.dig("product", "name")
  end

  test "answers 422 for an empty list or an invalid quantity" do
    receive([])
    assert_response :unprocessable_entity
    assert_equal "empty_items", response.parsed_body.dig("error", "details", "code")

    receive([ { product_id: @tacos.id, qty: 0 } ])
    assert_equal "invalid_qty", response.parsed_body.dig("error", "details", "code")
  end

  test "a product of another company answers 404 and nothing changes" do
    assert_no_difference -> { StockMovement.count } do
      receive([ { product_id: products(:one).id, qty: 1 } ])
    end
    assert_response :not_found
  end

  test "a company with the inventory module turned off is refused" do
    @company.update!(disabled_modules: [ "inventory" ])

    receive([ { product_id: @tacos.id, qty: 1 } ])

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end
end
