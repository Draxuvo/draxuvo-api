require "test_helper"

# Spec 058: «Cobro solo por jefes» en la venta de mostrador (US1 y la cola de US3). contracts/api.md.
class Api::V1::SalesBossOnlyTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/sales".freeze

  setup do
    @company = companies(:pos_co)
    @admin = users(:pos_admin)
    @owner = users(:pos_owner)
    @staff = users(:pos_staff)
    @staff2 = users(:pos_staff2)
    @cuaderno = products(:pos_cuaderno)
  end

  def headers(user) = auth_headers(user, @company)

  def json = response.parsed_body

  def code = json.dig("error", "details", "code")

  def turn_on! = @company.update!(boss_only_charge: true)

  def charge(sale, user, key: nil)
    extra = key ? { "Idempotency-Key" => key } : {}
    post "#{BASE}/#{sale.id}/charge", params: { lock_version: sale.reload.lock_version, payments: [ { method: "cash", amount_received: "500" } ] },
                                      headers: headers(user).merge(extra), as: :json
  end

  def submit(sale, user = @staff, lock_version: sale.reload.lock_version)
    post "#{BASE}/#{sale.id}/submit", params: { lock_version: lock_version }, headers: headers(user), as: :json
  end

  def return_sale(sale, user = @admin)
    post "#{BASE}/#{sale.id}/return", headers: headers(user), as: :json
  end

  # --- (a) opción apagada ---

  test "with the option off staff charges the sale it opened as today" do
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    charge(sale, @staff)
    assert_response :ok
    assert sale.reload.status_paid?
  end

  test "with the option off the sale has no submit action nor blocked reason" do
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    get "#{BASE}/#{sale.id}", headers: headers(@staff)
    assert_equal %w[add_item charge discard], json["actions"]
    assert_nil json["charge_blocked_reason"]
  end

  # --- (b) el personal no cobra ---

  test "with the option on staff gets 403 charge_boss_only and nothing changes" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    stock = @cuaderno.reload.stock

    assert_no_difference [ "Ticket.count", "TicketPayment.count", "StockMovement.count" ] do
      charge(sale, @staff)
    end
    assert_response :forbidden
    assert_equal "charge_boss_only", code
    assert sale.reload.status_open?
    assert_equal stock, @cuaderno.reload.stock
  end

  # --- (c) lo previo al cobro sigue igual ---

  test "with the option on staff still edits and discards a sale in capture" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    post "#{BASE}/#{sale.id}/items", params: { product_id: @cuaderno.id }, headers: headers(@staff), as: :json
    assert_response :ok
    item = sale.sale_items.first
    patch "#{BASE}/#{sale.id}/items/#{item.id}", params: { quantity: 3 }, headers: headers(@staff), as: :json
    assert_response :ok
    delete "#{BASE}/#{sale.id}/items/#{item.id}", headers: headers(@staff)
    assert_response :ok
    delete "#{BASE}/#{sale.id}", headers: headers(@staff)
    assert_response :no_content
  end

  # --- (d) pasar a cobro ---

  test "staff sends its sale to charge" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 2 ])
    submit(sale)
    assert_response :ok
    assert_not_nil json["submitted_at"]
    assert_equal [], json["actions"]
    assert_equal "boss_only", json["charge_blocked_reason"]
    assert sale.reload.submitted?
  end

  test "an empty sale cannot be sent to charge" do
    turn_on!
    sale = open_sale(@staff)
    submit(sale)
    assert_response :unprocessable_entity
    assert_equal "nothing_to_submit", code
  end

  test "sending twice answers already_submitted" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    submit(sale)
    submit(sale)
    assert_response :unprocessable_entity
    assert_equal "already_submitted", code
  end

  test "a stale lock_version answers 409" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    submit(sale, lock_version: 0)
    assert_response :conflict
    assert_equal "stale_object", code
    assert_nil sale.reload.submitted_at
  end

  # --- (e) una venta lista no la toca el cajero ---

  test "staff cannot edit nor discard a sale ready to charge" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    item = sale.sale_items.first
    submit(sale)

    post "#{BASE}/#{sale.id}/items", params: { product_id: @cuaderno.id }, headers: headers(@staff), as: :json
    assert_response :forbidden
    assert_equal "sale_submitted", code
    patch "#{BASE}/#{sale.id}/items/#{item.id}", params: { quantity: 3 }, headers: headers(@staff), as: :json
    assert_response :forbidden
    assert_equal "sale_submitted", code
    delete "#{BASE}/#{sale.id}/items/#{item.id}", headers: headers(@staff)
    assert_response :forbidden
    delete "#{BASE}/#{sale.id}", headers: headers(@staff)
    assert_response :forbidden
    assert_equal "sale_submitted", code
    assert_equal 1, sale.reload.sale_items.count
  end

  # --- (f) el jefe cobra ---

  test "the admin charges the sale another cashier sent" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    submit(sale)
    get "#{BASE}/#{sale.id}", headers: headers(@admin)
    assert_equal %w[add_item charge discard return], json["actions"]
    assert_nil json["charge_blocked_reason"]

    charge(sale, @admin)
    assert_response :ok
    assert sale.reload.status_paid?
    assert_equal @admin.id, sale.ticket.charged_by_id
  end

  test "the owner charges a sale still in capture" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    charge(sale, @owner)
    assert_response :ok
  end

  # --- (g) regresar ---

  test "a boss returns the sale to its cashier, who can edit it again" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    submit(sale)

    return_sale(sale, @staff)
    assert_response :forbidden

    return_sale(sale)
    assert_response :ok
    assert_nil json["submitted_at"]
    assert_not_nil json["returned_at"]
    assert_equal @admin.id, json.dig("returned_by", "id")

    post "#{BASE}/#{sale.id}/items", params: { product_id: @cuaderno.id }, headers: headers(@staff), as: :json
    assert_response :ok
  end

  test "returning a sale that is not ready answers not_submitted" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    return_sale(sale)
    assert_response :unprocessable_entity
    assert_equal "not_submitted", code
  end

  # --- (h) acciones ---

  test "staff in capture with items has submit and the blocked reason" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    get "#{BASE}/#{sale.id}", headers: headers(@staff)
    assert_equal %w[add_item discard submit], json["actions"]
    assert_equal "boss_only", json["charge_blocked_reason"]

    empty = open_sale(@staff)
    get "#{BASE}/#{empty.id}", headers: headers(@staff)
    assert_equal %w[add_item discard], json["actions"]
  end

  # --- (i) con la opción apagada no hay pasar a cobro ---

  test "submit and return with the option off answer charge_policy_off" do
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    submit(sale)
    assert_response :unprocessable_entity
    assert_equal "charge_policy_off", code

    sale.update_columns(submitted_at: Time.current)
    return_sale(sale)
    assert_response :unprocessable_entity
    assert_equal "charge_policy_off", code
  end

  # --- (j) solo quien la abrió la pasa a cobro ---

  test "a boss or another cashier cannot send the sale to charge" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    submit(sale, @admin)
    assert_response :forbidden
    submit(sale, @staff2)
    assert_response :not_found
    assert_nil sale.reload.submitted_at
  end

  # --- (k) un cobro rechazado no gasta la llave de idempotencia (R11) ---

  test "a rejected charge does not store its idempotency key" do
    turn_on!
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    charge(sale, @staff, key: "boss-only-1")
    assert_response :forbidden

    @company.update!(boss_only_charge: false)
    charge(sale, @staff, key: "boss-only-1")
    assert_response :ok
    assert sale.reload.status_paid?
  end

  # --- cola «Por cobrar» (US3) ---

  test "the queue lists ready sales of every cashier, oldest first, only for bosses" do
    turn_on!
    first = open_sale(@staff, [ @cuaderno, 1 ])
    second = open_sale(@staff2, [ @cuaderno, 2 ])
    open_sale(@staff, [ @cuaderno, 1 ]) # en captura: no aparece
    submit(first)
    travel 1.minute do
      submit(second, @staff2)
    end

    get BASE, params: { queue: 1 }, headers: headers(@admin)
    assert_response :ok
    assert_equal [ first.id, second.id ], json["results"].map { |row| row["id"] }
    assert json.key?("info")

    get BASE, params: { queue: 1 }, headers: headers(@staff)
    assert_response :forbidden
  end

  test "with the option off the queue is empty" do
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    sale.update_columns(submitted_at: Time.current)
    get BASE, params: { queue: 1 }, headers: headers(@admin)
    assert_response :ok
    assert_equal [], json["results"]
  end
end
