require "test_helper"

class Api::V1::Restaurant::DeliveriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @check = checks(:open_check)
  end

  def deliver(item, user: users(:resto_waiter))
    post "/api/v1/restaurant/checks/#{@check.id}/items/#{item.id}/deliver", headers: auth_headers(user, @company), as: :json
  end

  test "delivers a ready item and stamps the time" do
    deliver(check_items(:item_ready))

    assert_response :ok
    item = check_items(:item_ready).reload
    assert item.status_delivered?
    assert item.delivered_at.present?
    assert_equal "delivered", response.parsed_body["items"].find { |i| i["id"] == item.id }["status"]
  end

  test "an item that is not ready cannot be delivered" do
    deliver(check_items(:item_preparing))

    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body.dig("error", "details", "code")
    assert check_items(:item_preparing).reload.status_preparing?
  end

  test "delivering twice answers 422 the second time" do
    deliver(check_items(:item_ready))
    deliver(check_items(:item_ready))

    assert_response :unprocessable_entity
  end

  test "any waiter can deliver on a check that is not theirs" do
    deliver(check_items(:item_ready), user: users(:resto_waiter2))

    assert_response :ok
  end

  test "an item of another check is not found under this one" do
    deliver(check_items(:closed_item))

    assert_response :not_found
  end

  test "a check of another company is not found" do
    post "/api/v1/restaurant/checks/#{@check.id}/items/#{check_items(:item_ready).id}/deliver",
         headers: auth_headers(users(:pro_co_owner), companies(:pro_co)), as: :json

    assert_response :not_found
  end

  test "a delivered item stays counted in the total" do
    before = @check.reload.total
    deliver(check_items(:item_ready))

    assert_equal before, @check.reload.total
  end
end
