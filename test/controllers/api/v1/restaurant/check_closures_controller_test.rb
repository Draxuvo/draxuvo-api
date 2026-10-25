require "test_helper"

class Api::V1::Restaurant::CheckClosuresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @check = checks(:takeout_check)
  end

  def close(reason, user = users(:resto_owner))
    post "/api/v1/restaurant/checks/#{@check.id}/close", params: { reason: reason }, headers: auth_headers(user, @company), as: :json
  end

  test "a boss closes a check with nothing to charge" do
    close("Cortesía de la casa")

    assert_response :created
    assert_equal "closed", response.parsed_body.dig("check", "status")
    assert_equal "0.00", format("%.2f", response.parsed_body.dig("ticket", "total"))
    assert_equal "Cortesía de la casa", response.parsed_body.dig("ticket", "notes")
  end

  test "the reason is required" do
    close(" ")

    assert_response :unprocessable_entity
    assert_equal "reason_required", response.parsed_body.dig("error", "details", "code")
  end

  test "a waiter cannot close" do
    close("x", users(:resto_waiter2))

    assert_response :forbidden
  end

  test "a check with a balance cannot be closed this way" do
    @check = checks(:open_check)
    close("x")

    assert_response :unprocessable_entity
    assert_equal "not_zero_total", response.parsed_body.dig("error", "details", "code")
  end

  test "drafts are discarded when closing in zero" do
    @check.check_items.create!(company: @company, product: products(:resto_sopa), name: "Sopa", unit_price: 55, quantity: 1)
    close("Se retiraron")

    assert_response :created
    assert_equal 0, @check.check_items.count
  end
end
