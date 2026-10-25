require "test_helper"

class Api::V1::Restaurant::PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @check = settle_check(checks(:open_check)) # total 155
    @headers = auth_headers(users(:resto_waiter), @company)
  end

  def pay(body, headers = @headers)
    post "/api/v1/restaurant/checks/#{@check.id}/payments", params: body, headers: headers, as: :json
  end

  test "a partial payment leaves the check open with the balance" do
    pay({ method: "cash", amount: "55", amount_received: "100" })

    assert_response :created
    body = response.parsed_body
    assert_equal "open", body.dig("check", "status")
    assert_equal "100.00", body.dig("check", "balance")
    assert_equal "45.00", body.dig("payment", "change_given")
    assert_nil body["ticket"]
  end

  test "the payment that covers the balance closes the check and returns the ticket" do
    pay({ method: "cash", amount: "55", amount_received: "100" })
    pay({ method: "card", amount: "100", reference: "A8812" })

    assert_response :created
    body = response.parsed_body
    assert_equal "closed", body.dig("check", "status")
    assert_equal "mixed", body.dig("ticket", "payment_method")
    assert_equal %w[cash card], body.dig("ticket", "payments").map { |p| p["method"] }
    assert_equal "Mesa 1", "Mesa #{body.dig('ticket', 'check', 'table')}"
    assert_equal "A8812", body.dig("ticket", "payments", 1, "reference")
  end

  test "a card payment without a reference answers 422" do
    pay({ method: "card", amount: "50" })

    assert_response :unprocessable_entity
    assert_equal "reference_required", response.parsed_body.dig("error", "details", "code")
  end

  test "incomplete items ask for confirmation" do
    unsettle_open_check
    pay({ method: "cash", amount_received: "500" })

    assert_response :unprocessable_entity
    assert_equal "incomplete_items", response.parsed_body.dig("error", "details", "code")
    assert_equal 3, response.parsed_body.dig("error", "details", "pending")

    pay({ method: "cash", amount_received: "500", confirm_incomplete: true })
    assert_response :created
  end

  test "repeating the same Idempotency-Key does not charge twice" do
    key = { "Idempotency-Key" => SecureRandom.uuid }

    assert_difference -> { CheckPayment.count }, 1 do
      3.times { pay({ method: "card", amount: "50", reference: "A1" }, @headers.merge(key)) }
    end
    assert_response :created
    assert_equal "105.00", response.parsed_body.dig("check", "balance")
  end

  test "twenty retries of the same payment charge once" do
    key = { "Idempotency-Key" => SecureRandom.uuid }

    assert_difference -> { CheckPayment.count }, 1 do
      20.times { pay({ method: "cash", amount_received: "500" }, @headers.merge(key)) }
    end
    assert_equal 1, Ticket.where(check: @check).count
  end

  test "another waiter cannot charge a check that is not theirs, a boss can" do
    pay({ method: "cash", amount_received: "500" }, auth_headers(users(:resto_waiter2), @company))
    assert_response :forbidden
    assert_equal 0, @check.check_payments.count

    pay({ method: "cash", amount_received: "500" }, auth_headers(users(:resto_owner), @company))
    assert_response :created
  end

  test "a check that is already closed rejects payments" do
    pay({ method: "cash", amount_received: "500" })
    pay({ method: "cash", amount_received: "500" })

    assert_response :unprocessable_entity
    assert_equal "check_not_open", response.parsed_body.dig("error", "details", "code")
  end

  test "a check of another company is not found" do
    pay({ method: "cash", amount_received: "500" }, auth_headers(users(:pro_co_owner), companies(:pro_co)))

    assert_response :not_found
  end

  test "closing deducts the inventory of the tracked product" do
    assert_difference -> { products(:resto_tacos).reload.stock }, -1 do
      pay({ method: "cash", amount_received: "500" })
    end
  end
end
