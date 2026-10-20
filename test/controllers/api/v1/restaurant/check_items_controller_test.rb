require "test_helper"

class Api::V1::Restaurant::CheckItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @check = checks(:takeout_check)
    @headers = auth_headers(users(:resto_waiter), @company)
  end

  def add(product, quantity: 1, note: nil)
    post "/api/v1/restaurant/checks/#{@check.id}/items",
         params: { product_id: product.id, quantity: quantity, note: note }.compact, headers: @headers, as: :json
  end

  test "adds an item copying the name and price of the product" do
    add(products(:resto_tacos), quantity: 2, note: "sin cebolla")

    assert_response :created
    item = response.parsed_body["items"].first
    assert_equal "Tacos al pastor", item["name"]
    assert_equal "70.00", item["unit_price"]
    assert_equal 2, item["quantity"]
    assert_equal "sin cebolla", item["note"]
    assert_equal "draft", item["status"]
  end

  test "the price stays the one at the time even if the menu changes" do
    add(products(:resto_tacos))
    products(:resto_tacos).update!(price: 99)

    assert_equal "70.00", @check.check_items.first.unit_price.to_s("F").then { |p| format("%.2f", p) }
  end

  test "a sold out product cannot be added" do
    add(products(:resto_cola), quantity: 5)

    assert_response :unprocessable_entity
    assert_equal "sold_out", response.parsed_body.dig("error", "details", "code")
    assert_equal 0, @check.check_items.count
  end

  test "an untracked product can always be added" do
    add(products(:resto_sopa), quantity: 50)

    assert_response :created
  end

  test "a product that is not available in the menu is not found" do
    products(:resto_agua).update!(available: false)
    add(products(:resto_agua))

    assert_response :not_found
  end

  test "a product of another company is not found" do
    add(products(:one))

    assert_response :not_found
  end

  test "a closed check does not take items" do
    @check = checks(:closed_check)
    add(products(:resto_sopa))

    assert_response :unprocessable_entity
    assert_equal "check_not_open", response.parsed_body.dig("error", "details", "code")
  end

  test "edits the quantity and note of a draft" do
    add(products(:resto_sopa))
    item = @check.check_items.first
    patch "/api/v1/restaurant/checks/#{@check.id}/items/#{item.id}", params: { quantity: 3, note: "caliente" }, headers: @headers, as: :json

    assert_response :ok
    assert_equal [ 3, "caliente" ], [ item.reload.quantity, item.note ]
  end

  test "a sent item cannot be edited or removed" do
    sent = check_items(:item_new)
    patch "/api/v1/restaurant/checks/#{sent.check_id}/items/#{sent.id}", params: { quantity: 9 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "not_draft", response.parsed_body.dig("error", "details", "code")

    delete "/api/v1/restaurant/checks/#{sent.check_id}/items/#{sent.id}", headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert CheckItem.exists?(sent.id)
  end

  test "removes a draft without leaving a trace" do
    add(products(:resto_sopa))
    item = @check.check_items.first
    delete "/api/v1/restaurant/checks/#{@check.id}/items/#{item.id}", headers: @headers, as: :json

    assert_response :ok
    assert_not CheckItem.exists?(item.id)
  end

  test "any waiter can add to a check that is not theirs" do
    add_headers = auth_headers(users(:resto_waiter2), @company)
    post "/api/v1/restaurant/checks/#{checks(:open_check).id}/items", params: { product_id: products(:resto_sopa).id },
                                                                        headers: add_headers, as: :json

    assert_response :created
  end

  test "a supply cannot be added to a check (spec 016)" do
    lime = @company.products.create!(name: "Limón", sku: "LIM", product_type: product_types(:resto_co_supply), stock: 5)
    add(lime)
    assert_response :not_found
  end
end
