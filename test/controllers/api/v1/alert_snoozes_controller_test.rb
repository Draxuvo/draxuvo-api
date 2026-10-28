require "test_helper"

# Posponer una alerta de tiempo (spec 045, FR-005a y FR-005b).
class Api::V1::AlertSnoozesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/alerts/snooze".freeze

  setup do
    @company = companies(:resto_co)
    @owner = create_member(@company, role: :owner)
    @admin = create_member(@company, role: :admin)
    @round = kitchen_orders(:first_round)
    Product.where(company_id: @company.id).update_all(stock: 1000) # que el stock bajo no mezcle las cuentas
    KitchenOrder.where(id: @round.id).update_all(sent_at: 15.minutes.ago)
    @key = "ko:#{@round.id}:st:#{stations(:kitchen).id}"
  end

  def json = JSON.parse(response.body)

  def snooze!(minutes: 60, user: @owner, kind: "kitchen_wait", key: @key)
    post PATH, params: { kind: kind, subject_key: key, minutes: minutes }, headers: auth_headers(user, @company), as: :json
  end

  def alerts = (get "/api/v1/alerts", headers: auth_headers(@owner, @company); json)

  test "snoozing takes the alert out of the count and lists it aside with its deadline" do
    snooze!(minutes: 60)

    assert_response :created
    assert_equal "kitchen_wait:#{@key}", json["id"]
    assert_in_delta 60.minutes.from_now.to_f, Time.zone.parse(json["snoozed_until"]).to_f, 5

    body = alerts
    assert_equal 0, body["count"]
    assert_empty body["results"]
    assert_equal 1, body["snoozed"].size
    assert_equal @owner.full_name, body["snoozed"].first["snoozed_by"]
  end

  test "30, 60 and 120 minutes are valid and any other value is rejected" do
    [ 30, 60, 120 ].each do |minutes|
      snooze!(minutes: minutes)
      assert_response :created
    end

    [ 0, 15, 45, 1000 ].each do |minutes|
      snooze!(minutes: minutes)
      assert_response :unprocessable_entity
    end
  end

  test "low stock and unknown kinds cannot be snoozed" do
    snooze!(kind: "low_stock", key: "product:1")
    assert_response :unprocessable_entity
    assert_equal I18n.t("alerts.errors.not_snoozable"), json.dig("error", "details", 0)

    snooze!(kind: "nope")
    assert_response :unprocessable_entity
  end

  test "snoozing again moves the deadline and does not duplicate the row" do
    snooze!(minutes: 30)
    assert_no_difference -> { AlertSnooze.count } do
      snooze!(minutes: 120, user: @admin)
    end
    assert_equal @admin.id, AlertSnooze.last.user_id
    assert_in_delta 120.minutes.from_now.to_f, AlertSnooze.last.snoozed_until.to_f, 5
  end

  test "a snooze is shared by every boss of the company" do
    snooze!(user: @admin)
    get "/api/v1/alerts", headers: auth_headers(@owner, @company)
    assert_equal 0, json["count"]
  end

  test "it returns when the snooze expires and the element still has not moved on" do
    snooze!(minutes: 30)
    AlertSnooze.update_all(snoozed_until: 1.minute.ago)

    body = alerts
    assert_equal 1, body["count"]
    assert_empty body["snoozed"]
    assert_equal 0, AlertSnooze.count
  end

  test "the snooze is lost when the element moves on and a new delay starts clean" do
    snooze!
    CheckItem.where(id: check_items(:item_new).id).update_all(status: 2, preparing_at: Time.current)
    alerts
    assert_equal 0, AlertSnooze.count
  end

  test "removing the snooze brings the alert back, and removing a missing one is fine" do
    snooze!
    delete PATH, params: { kind: "kitchen_wait", subject_key: @key }, headers: auth_headers(@owner, @company)
    assert_response :no_content
    assert_equal 1, alerts["count"]

    delete PATH, params: { kind: "kitchen_wait", subject_key: @key }, headers: auth_headers(@owner, @company)
    assert_response :no_content
  end

  test "staff cannot snooze" do
    waiter = create_member(@company, role: :staff)
    snooze!(user: waiter)
    assert_response :forbidden
    assert_equal 0, AlertSnooze.count
  end

  test "a snooze only applies in its own company" do
    snooze!
    other = companies(:pro_co)
    assert_equal 0, other.alert_snoozes.count
    assert_equal 1, @company.alert_snoozes.count
  end
end
