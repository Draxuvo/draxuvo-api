require "test_helper"

class Api::V1::SalesIdempotencyTest < ActionDispatch::IntegrationTest
  setup do
    @staff = users(:pos_staff)
    @headers = auth_headers(@staff, companies(:pos_co))
    @sale = open_sale(@staff, [ products(:pos_cuaderno), 2 ])
  end

  def charge(key: nil, sale: @sale)
    headers = key ? @headers.merge("Idempotency-Key" => key) : @headers
    post "/api/v1/sales/#{sale.id}/charge",
         params: { lock_version: sale.lock_version, payments: [ { method: "cash", amount_received: "100" } ] }, headers: headers, as: :json
  end

  test "the same key charges once, stores the answer and does not discount stock twice" do
    assert_difference -> { Ticket.where(sale: @sale).count }, 1 do
      charge(key: "sale-1")
    end
    assert_response :ok
    body = response.body
    stock = products(:pos_cuaderno).reload.stock

    assert_no_difference -> { Ticket.count } do
      charge(key: "sale-1")
    end
    assert_response :ok
    assert_equal body, response.body
    assert_equal stock, products(:pos_cuaderno).reload.stock
    assert_equal 1, StockMovement.where(sale: @sale).count
  end

  test "without a key a second charge is still rejected because the sale is no longer open" do
    charge
    assert_response :ok
    charge
    assert_response :unprocessable_entity
    assert_equal 1, StockMovement.where(sale: @sale).count
  end

  test "a failed charge is not stored and can be retried with the same key" do
    post "/api/v1/sales/#{@sale.id}/charge", params: { lock_version: @sale.lock_version, payments: [ { method: "cash", amount_received: "1" } ] },
                                              headers: @headers.merge("Idempotency-Key" => "retry"), as: :json
    assert_response :unprocessable_entity
    assert_nil IdempotencyKey.find_by(key: "retry")

    charge(key: "retry")
    assert_response :ok
  end
end
