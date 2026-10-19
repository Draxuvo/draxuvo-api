require "test_helper"

class Api::V1::Restaurant::ItemCancellationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @check = checks(:open_check)
  end

  def cancel(item, reason, user: users(:resto_waiter))
    post "/api/v1/restaurant/checks/#{@check.id}/items/#{item.id}/cancel", params: { reason: reason },
                                                                            headers: auth_headers(user, @company), as: :json
  end

  test "cancels a new item and answers the check without it in the total" do
    cancel(check_items(:item_new), "El cliente cambió de idea")

    assert_response :ok
    body = response.parsed_body
    item = body["items"].find { |i| i["id"] == check_items(:item_new).id }
    assert_equal "cancelled", item["status"]
    assert_equal "85.00", body["total"]
  end

  test "the kitchen board shows it as cancelled" do
    cancel(check_items(:item_new), "x")
    get "/api/v1/restaurant/stations/#{stations(:kitchen).id}/board", headers: auth_headers(users(:resto_waiter), @company)

    statuses = response.parsed_body["orders"].flat_map { |o| o["items"].map { |i| [ i["name"], i["status"] ] } }.to_h
    assert_equal "cancelled", statuses["Tacos al pastor"]
  end

  test "a waiter cannot cancel an item in preparation" do
    cancel(check_items(:item_preparing), "x")

    assert_response :forbidden
    assert check_items(:item_preparing).reload.status_preparing?
  end

  test "a boss cancels an item in preparation and it stays on record" do
    cancel(check_items(:item_preparing), "Se quemó", user: users(:resto_manager))

    assert_response :ok
    item = check_items(:item_preparing).reload
    assert_equal [ "Se quemó", users(:resto_manager) ], [ item.cancel_reason, item.cancelled_by ]
  end

  test "the reason is required" do
    cancel(check_items(:item_new), "")

    assert_response :unprocessable_entity
    assert_equal "reason_required", response.parsed_body.dig("error", "details", "code")
  end

  test "a check of another company is not found" do
    post "/api/v1/restaurant/checks/#{@check.id}/items/#{check_items(:item_new).id}/cancel", params: { reason: "x" },
         headers: auth_headers(users(:pro_co_owner), companies(:pro_co)), as: :json

    assert_response :not_found
  end

  test "an empty check is cancelled and frees the table" do
    check = @company.checks.create!(dining_table: dining_tables(:table_3), opened_by: users(:resto_waiter), waiter: users(:resto_waiter),
                                    opened_at: Time.current)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: auth_headers(users(:resto_waiter), @company), as: :json

    assert_response :ok
    assert_not dining_tables(:table_3).occupied?
  end
end
