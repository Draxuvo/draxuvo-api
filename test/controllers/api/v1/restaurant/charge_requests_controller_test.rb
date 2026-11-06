require "test_helper"

# Spec 058 (US4, FR-023): «Pedir cobro» en una cuenta de mesa con «Cobro solo por jefes».
class Api::V1::Restaurant::ChargeRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = companies(:resto_co)
    @company.update!(boss_only_charge: true)
    @check = checks(:open_check) # mesero: resto_waiter, con artículos mandados y saldo
    @waiter = users(:resto_waiter)
  end

  def request_charge(user = @waiter, check = @check)
    post "/api/v1/restaurant/checks/#{check.id}/charge_request", headers: auth_headers(user, @company), as: :json
  end

  def json = response.parsed_body

  def code = json.dig("error", "details", "code")

  test "the waiter asks for the charge: the check is marked and the bosses are notified" do
    assert_enqueued_with(job: Push::ChargePendingJob, args: [ "check", @check.id, @waiter.id ]) do
      request_charge
    end
    assert_response :ok
    assert_not_nil json["charge_requested_at"]
    assert_equal @waiter.id, json.dig("charge_requested_by", "id")
    assert_equal "boss_only", json["charge_blocked_reason"]
    assert_not_includes json["allowed_actions"], "pay"
    assert_not_includes json["allowed_actions"], "request_charge"
    assert @check.reload.charge_requested?
  end

  test "before asking, the waiter has request_charge and not pay" do
    get "/api/v1/restaurant/checks/#{@check.id}", headers: auth_headers(@waiter, @company)
    assert_includes json["allowed_actions"], "request_charge"
    assert_not_includes json["allowed_actions"], "pay"
  end

  test "a boss can also ask; another waiter cannot" do
    request_charge(users(:resto_waiter2))
    assert_response :forbidden

    request_charge(users(:resto_owner))
    assert_response :ok
  end

  test "with the option off it answers charge_policy_off" do
    @company.update!(boss_only_charge: false)
    request_charge
    assert_response :unprocessable_entity
    assert_equal "charge_policy_off", code
  end

  test "a check without sent items cannot ask for the charge" do
    check = checks(:takeout_check)
    request_charge(users(:resto_waiter2), check)
    assert_response :unprocessable_entity
    assert_equal "nothing_to_submit", code
  end

  test "adding an item clears the mark" do
    request_charge
    post "/api/v1/restaurant/checks/#{@check.id}/items", params: { product_id: products(:resto_tacos).id, quantity: 1 },
                                                        headers: auth_headers(@waiter, @company), as: :json
    assert_response :created
    assert_nil json["charge_requested_at"]
    assert_nil @check.reload.charge_requested_at
  end

  test "the plan shows the mark and the overview counts it for bosses" do
    request_charge
    get "/api/v1/restaurant/tables", headers: auth_headers(users(:resto_owner), @company)
    assert_response :ok
    table = json["results"].find { |t| t.dig("check", "id") == @check.id }
    assert_not_nil table.dig("check", "charge_requested_at")
    assert_equal 1, json.dig("overview", "charge_requested")
  end
end
