require "test_helper"

class Api::V1::Restaurant::ChecksControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  def headers_for(user) = auth_headers(user, @company)

  test "opens a check on a free table, at the caller's name" do
    assert_difference -> { Check.count }, 1 do
      post "/api/v1/restaurant/checks", params: { dining_table_id: dining_tables(:table_3).id },
                                        headers: headers_for(users(:resto_waiter)), as: :json
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "open", body["status"]
    assert_equal "3", body.dig("table", "name")
    assert_equal users(:resto_waiter).id, body.dig("waiter", "id")
    assert_empty body["items"]
  end

  test "an occupied table answers 422 table_occupied" do
    post "/api/v1/restaurant/checks", params: { dining_table_id: dining_tables(:table_1).id },
                                      headers: headers_for(users(:resto_waiter2)), as: :json

    assert_response :unprocessable_entity
    assert_equal "table_occupied", response.parsed_body.dig("error", "details", "code")
  end

  test "opens a takeout check with a name" do
    post "/api/v1/restaurant/checks", params: { takeout_name: "María" }, headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :created
    assert_equal "María", response.parsed_body["takeout_name"]
    assert_nil response.parsed_body["table"]
  end

  test "a takeout check without a name is invalid" do
    post "/api/v1/restaurant/checks", params: { takeout_name: " " }, headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :unprocessable_entity
  end

  test "a table of another company is not found" do
    foreign = companies(:pro_co).dining_tables.create!(name: "X")
    post "/api/v1/restaurant/checks", params: { dining_table_id: foreign.id }, headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :not_found
  end

  test "shows the check with items, statuses and actions" do
    get "/api/v1/restaurant/checks/#{checks(:open_check).id}", headers: headers_for(users(:resto_waiter))

    assert_response :ok
    body = response.parsed_body
    assert_equal "155.00", body["total"]
    assert_equal %w[draft new preparing ready], body["items"].map { |i| i["status"] }.sort_by { |s| %w[draft new preparing ready].index(s) }
    assert_includes body["allowed_actions"], "pay"
    ready = body["items"].find { |i| i["status"] == "ready" }
    assert_equal %w[deliver], ready["allowed_actions"], "cancelar algo listo es del encargado"
  end

  test "another waiter does not get the pay action" do
    get "/api/v1/restaurant/checks/#{checks(:open_check).id}", headers: headers_for(users(:resto_waiter2))

    assert_not_includes response.parsed_body["allowed_actions"], "pay"
    assert_includes response.parsed_body["allowed_actions"], "add_item"
  end

  test "a check of another company is not found" do
    get "/api/v1/restaurant/checks/#{checks(:open_check).id}",
        headers: auth_headers(users(:pro_co_owner), companies(:pro_co))

    assert_response :not_found
  end

  test "a boss reassigns the waiter" do
    patch "/api/v1/restaurant/checks/#{checks(:open_check).id}", params: { waiter_id: users(:resto_waiter2).id },
                                                                 headers: headers_for(users(:resto_manager)), as: :json

    assert_response :ok
    assert_equal users(:resto_waiter2), checks(:open_check).reload.waiter
  end

  test "a waiter cannot reassign" do
    patch "/api/v1/restaurant/checks/#{checks(:open_check).id}", params: { waiter_id: users(:resto_waiter2).id },
                                                                 headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :forbidden
  end

  test "reassigning to someone outside the company is rejected" do
    patch "/api/v1/restaurant/checks/#{checks(:open_check).id}", params: { waiter_id: users(:pro_staff).id },
                                                                 headers: headers_for(users(:resto_manager)), as: :json

    assert_response :unprocessable_entity
    assert_equal "waiter_not_member", response.parsed_body.dig("error", "details", "code")
  end

  test "cancels an empty check and frees the table" do
    check = @company.checks.create!(dining_table: dining_tables(:table_4), opened_by: users(:resto_waiter),
                                    waiter: users(:resto_waiter), opened_at: Time.current)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :ok
    assert_equal "cancelled", response.parsed_body["status"]
    assert_not dining_tables(:table_4).occupied?
  end

  test "a check with sent items cannot be cancelled" do
    post "/api/v1/restaurant/checks/#{checks(:open_check).id}/cancel", headers: headers_for(users(:resto_manager)), as: :json

    assert_response :unprocessable_entity
    assert_equal "has_sent_items", response.parsed_body.dig("error", "details", "code")
  end

  test "another waiter cannot cancel an empty check that is not theirs" do
    post "/api/v1/restaurant/checks/#{checks(:takeout_check).id}/cancel", headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :forbidden
  end

  test "drafts are discarded when an otherwise empty check is cancelled" do
    check = checks(:takeout_check)
    check.check_items.create!(company: @company, product: products(:resto_agua), name: "Agua", unit_price: 25, quantity: 1)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_waiter2)), as: :json

    assert_response :ok
    assert_equal 0, check.check_items.count
  end

  test "items carry the product id and its icons" do
    products(:resto_tacos).update!(icon: "taco")
    products(:resto_tacos).product_type.update!(icon: "utensils")

    get "/api/v1/restaurant/checks/#{checks(:open_check).id}", headers: headers_for(users(:resto_waiter))

    taco = response.parsed_body["items"].find { |i| i["name"] == "Tacos al pastor" }
    assert_equal products(:resto_tacos).id, taco["product_id"]
    assert_equal "taco", taco["icon"]
    assert_equal "utensils", taco["type_icon"]
  end
end
