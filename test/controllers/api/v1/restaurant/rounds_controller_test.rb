require "test_helper"

class Api::V1::Restaurant::RoundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @check = checks(:open_check)
    @headers = auth_headers(users(:resto_waiter), @company)
  end

  def send_round(headers = @headers)
    post "/api/v1/restaurant/checks/#{@check.id}/rounds", headers: headers, as: :json
  end

  test "sends the drafts and answers with the round" do
    send_round

    assert_response :created
    body = response.parsed_body
    assert_equal 2, body.dig("kitchen_order", "number")
    assert_equal [ "Agua de horchata" ], body["sent"].map { |i| i["name"] }
    assert_equal "Cocina", body.dig("sent", 0, "station", "name")
    assert_empty body["rejected"]
    assert_equal "new", body["check"]["items"].find { |i| i["name"] == "Agua de horchata" }["status"]
  end

  test "a second round does not change the first" do
    send_round
    @check.check_items.create!(company: @company, product: products(:resto_sopa), name: "Sopa", unit_price: 55, quantity: 1)
    send_round

    assert_response :created
    assert_equal 3, response.parsed_body.dig("kitchen_order", "number")
    assert_equal 1, check_items(:item_new).reload.kitchen_order.number
  end

  test "repeating the same Idempotency-Key does not create another round" do
    key = { "Idempotency-Key" => SecureRandom.uuid }

    assert_difference -> { KitchenOrder.count }, 1 do
      2.times { send_round(@headers.merge(key)) }
    end
    assert_response :created
  end

  test "twenty retries of the same send create a single round" do
    key = { "Idempotency-Key" => SecureRandom.uuid }

    assert_difference -> { KitchenOrder.count }, 1 do
      20.times { send_round(@headers.merge(key)) }
    end
  end

  test "a rejected item is reported and the rest goes out" do
    @check.check_items.create!(company: @company, product: products(:resto_cola), name: "Cola", unit_price: 30, quantity: 5)
    send_round

    assert_response :created
    body = response.parsed_body
    assert_equal [ "Cola" ], body["rejected"].map { |i| i["name"] }
    assert_equal "sold_out", body.dig("rejected", 0, "reason")
    assert_equal 1, body["sent"].size
  end

  test "nothing to send answers 422" do
    check_items(:item_draft).destroy!
    send_round

    assert_response :unprocessable_entity
    assert_equal "nothing_to_send", response.parsed_body.dig("error", "details", "code")
  end

  test "everything rejected answers 200 without a round" do
    check_items(:item_draft).destroy!
    @check.check_items.create!(company: @company, product: products(:resto_cola), name: "Cola", unit_price: 30, quantity: 5)

    assert_no_difference -> { KitchenOrder.count } do
      send_round
    end
    assert_response :ok
    assert_nil response.parsed_body["kitchen_order"]
  end

  test "another waiter can send the round of a check that is not theirs" do
    send_round(auth_headers(users(:resto_waiter2), @company))

    assert_response :created
  end

  test "sending for a check of another company is not found" do
    post "/api/v1/restaurant/checks/#{@check.id}/rounds", headers: auth_headers(users(:pro_co_owner), companies(:pro_co)), as: :json

    assert_response :not_found
  end
end
