require "test_helper"

class Api::V1::Restaurant::StationBoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @headers = auth_headers(users(:resto_waiter), @company)
  end

  def board(station) = get("/api/v1/restaurant/stations/#{station.id}/board", headers: @headers)

  test "the kitchen sees only its own pending items" do
    board(stations(:kitchen))

    assert_response :ok
    body = response.parsed_body
    assert_equal "Cocina", body.dig("station", "name")
    assert_equal "kitchen", body.dig("station", "kind")
    order = body["orders"].first
    assert_equal 1, order["number"]
    assert_equal "1", order["table"]
    assert_equal [ "Tacos al pastor", "Sopa del día" ], order["items"].map { |i| i["name"] }
    assert_equal "sin cebolla", order["items"].first["note"]
  end

  test "the bar sees none of the kitchen's items and nothing ready" do
    board(stations(:bar))

    assert_response :ok
    assert_empty response.parsed_body["orders"], "su cola ya está lista"
  end

  test "a ready item leaves the board" do
    check_items(:item_preparing).update!(status: :ready, ready_at: Time.current)
    board(stations(:kitchen))

    assert_equal [ "Tacos al pastor" ], response.parsed_body["orders"].flat_map { |o| o["items"].map { |i| i["name"] } }
  end

  test "a cancelled item shows as cancelled for a while" do
    check_items(:item_new).update!(status: :cancelled, cancelled_at: Time.current, cancel_reason: "x", cancelled_by: users(:resto_manager))
    board(stations(:kitchen))

    statuses = response.parsed_body["orders"].flat_map { |o| o["items"].map { |i| [ i["name"], i["status"] ] } }.to_h
    assert_equal "cancelled", statuses["Tacos al pastor"]

    travel 3.minutes do
      board(stations(:kitchen))
      names = response.parsed_body["orders"].flat_map { |o| o["items"].map { |i| i["name"] } }
      assert_not_includes names, "Tacos al pastor"
    end
  end

  test "orders come by arrival time" do
    later = checks(:takeout_check).kitchen_orders.create!(company: @company, sent_by: users(:resto_waiter2), sent_at: Time.current, number: 1)
    item = checks(:takeout_check).check_items.create!(company: @company, product: products(:resto_sopa), name: "Otra sopa", unit_price: 55, quantity: 1)
    item.update!(status: :new, kitchen_order: later, station: stations(:kitchen))
    board(stations(:kitchen))

    assert_equal [ "1", nil ], response.parsed_body["orders"].map { |o| o["table"] }
    assert_equal "Luis", response.parsed_body["orders"].last["takeout_name"]
  end

  test "a station of another company is not found" do
    foreign = companies(:pro_co).stations.create!(name: "Ajena")
    board(foreign)

    assert_response :not_found
  end

  test "answers 304 when nothing changed" do
    board(stations(:kitchen))
    etag = response.headers["ETag"]
    get "/api/v1/restaurant/stations/#{stations(:kitchen).id}/board", headers: @headers.merge("If-None-Match" => etag)

    assert_response :not_modified
  end

  test "advances one item" do
    post "/api/v1/restaurant/stations/#{stations(:kitchen).id}/items/#{check_items(:item_new).id}/advance", headers: @headers, as: :json

    assert_response :ok
    assert_equal "preparing", response.parsed_body["status"]
  end

  test "advancing twice from two devices answers 422 the second time" do
    path = "/api/v1/restaurant/stations/#{stations(:kitchen).id}/items/#{check_items(:item_preparing).id}/advance"
    post path, headers: @headers, as: :json
    post path, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body.dig("error", "details", "code")
  end

  test "advances a whole round" do
    post "/api/v1/restaurant/stations/#{stations(:kitchen).id}/kitchen_orders/#{kitchen_orders(:first_round).id}/advance", headers: @headers, as: :json

    assert_response :ok
    assert_equal %w[preparing ready], response.parsed_body["results"].map { |r| r["status"] }.sort_by { |s| %w[preparing ready].index(s) }
  end

  test "a person from another company cannot read the board" do
    get "/api/v1/restaurant/stations/#{stations(:kitchen).id}/board", headers: auth_headers(users(:pro_co_owner), companies(:pro_co))

    assert_response :not_found
  end
end
