require "test_helper"

# Spec 031: una suscripción suspendida bloquea la operación (403 subscription_suspended); solo se puede ver el
# estado y pagar. La URL de pago solo viaja al dueño y al administrador.
class Api::V1::SubscriptionGateTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @subscription = subscriptions(:pro_co)
    @subscription.update!(status: :suspended, suspended_at: Time.current, suspension_reason: "plan_change",
                          pending_invoice_url: "https://invoice.stripe.com/i/gate")
  end

  def details = response.parsed_body.dig("error", "details")

  test "the owner gets 403 on any operation with the reason, the plan, the cancel date and the pay url" do
    get "/api/v1/employees", headers: auth_headers(users(:pro_co_owner), @company)

    assert_response :forbidden
    assert_equal "subscription_suspended", details["code"]
    assert_equal "plan_change", details["reason"]
    assert_equal "pro", details["plan"]
    assert details["cancels_at"].present?
    assert_equal "https://invoice.stripe.com/i/gate", details["pay_url"]
  end

  test "staff gets the same 403 without the pay url" do
    [ users(:pro_staff) ].each do |user|
      get "/api/v1/work_orders", headers: auth_headers(user, @company)

      assert_response :forbidden
      assert_equal "subscription_suspended", details["code"]
      assert_not details.key?("pay_url"), "#{user.email} no debe recibir la URL de pago"
    end
  end

  test "the owner can still read the subscription to pay" do
    get "/api/v1/subscription", headers: auth_headers(users(:pro_co_owner), @company)

    assert_response :ok
    assert_equal "suspended", response.parsed_body["status"]
  end

  test "the super admin is never blocked" do
    get "/api/v1/employees", headers: auth_headers(users(:super_admin), @company)

    assert_response :ok
  end

  test "a branch follows the suspension of its parent company" do
    parent = companies(:enterprise_co)
    subscriptions(:enterprise_co).update!(status: :suspended, suspended_at: Time.current, suspension_reason: "payment_overdue")
    branch = Company.create!(name: "Sucursal suspendida", parent: parent)
    owner = create_member(branch, role: :owner)

    get "/api/v1/employees", headers: auth_headers(owner, branch)

    assert_response :forbidden
    assert_equal "subscription_suspended", details["code"]
  end

  test "once paid the company operates again" do
    Subscriptions::ReactivateService.new(@subscription).call

    get "/api/v1/employees", headers: auth_headers(users(:pro_co_owner), @company)

    assert_response :ok
  end

  test "a past due company keeps its access during the grace period" do
    @subscription.update!(status: :past_due, past_due_since: 2.days.ago, suspended_at: nil, suspension_reason: nil)

    get "/api/v1/employees", headers: auth_headers(users(:pro_co_owner), @company)

    assert_response :ok
  end
end
