require "test_helper"

class Api::V1::SalesCancelTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pos_co)
    @staff = users(:pos_staff)
    @sale = open_sale(@staff, [ products(:pos_cuaderno), 2 ])
    charge_cash(@sale, @staff, received: 100)
  end

  def cancel(user, reason: "Cliente devolvió todo", sale: @sale)
    post "/api/v1/sales/#{sale.id}/cancel", params: { reason: reason }, headers: auth_headers(user, @company), as: :json
  end

  def json = response.parsed_body

  test "an administrator cancels with a reason and the stock comes back" do
    cancel(users(:pos_admin))

    assert_response :ok
    assert_equal "cancelled", json["status"]
    assert_equal "Cliente devolvió todo", json["cancel_reason"]
    assert_equal users(:pos_admin).id, json.dig("cancelled_by", "id")
    assert_equal "voided", json.dig("ticket", "status")
    assert_equal %w[ticket], json["actions"]
    assert_equal 18, products(:pos_cuaderno).reload.stock
  end

  test "the owner can cancel too" do
    cancel(users(:pos_owner))
    assert_response :ok
  end

  test "staff cannot cancel, not even their own sale" do
    cancel(@staff)
    assert_response :forbidden
    assert @sale.reload.status_paid?
    assert_equal 16, products(:pos_cuaderno).reload.stock
  end

  test "the reason is required" do
    cancel(users(:pos_admin), reason: " ")
    assert_response :unprocessable_entity
    assert_equal "reason_required", json.dig("error", "details", "code")
    assert @sale.reload.status_paid?
  end

  test "cancelling twice is rejected without returning stock again" do
    cancel(users(:pos_admin))
    cancel(users(:pos_admin))
    assert_response :unprocessable_entity
    assert_equal "not_paid", json.dig("error", "details", "code")
    assert_equal 18, products(:pos_cuaderno).reload.stock
  end

  test "an open sale cannot be cancelled" do
    open = open_sale(@staff, [ products(:pos_pluma), 1 ])
    cancel(users(:pos_admin), sale: open)
    assert_response :unprocessable_entity
  end

  test "the ticket of a cancelled sale is marked and still downloadable" do
    cancel(users(:pos_admin))
    get "/api/v1/sales/#{@sale.id}/ticket", headers: auth_headers(users(:pos_admin), @company)
    assert_response :ok
    assert_equal "voided", json["status"]
    assert_equal "Cliente devolvió todo", json["void_reason"]

    get "/api/v1/sales/#{@sale.id}/ticket.pdf", params: { paper: "thermal80" }, headers: auth_headers(users(:pos_admin), @company)
    assert_response :ok
  end

  test "the cashier sees the cancelled state of their own sale" do
    cancel(users(:pos_admin))
    get "/api/v1/sales/#{@sale.id}", headers: auth_headers(@staff, @company)
    assert_response :ok
    assert_equal "cancelled", json["status"]
    assert_equal %w[ticket], json["actions"]
  end

  test "without the module there is no cancelling" do
    cancel(users(:pro_co_owner), sale: @sale)
    assert_response :forbidden
  end

  test "a cancelled sale appears under its status filter and not under paid" do
    cancel(users(:pos_admin))
    get "/api/v1/sales", params: { status: "cancelled" }, headers: auth_headers(users(:pos_admin), @company)
    assert_equal [ @sale.id ], json["results"].map { |s| s["id"] }
    get "/api/v1/sales", params: { status: "paid" }, headers: auth_headers(users(:pos_admin), @company)
    assert_empty json["results"]
  end
end
