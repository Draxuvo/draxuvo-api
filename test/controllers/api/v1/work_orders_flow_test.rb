require "test_helper"

# Flujo de órdenes de trabajo (spec 007, US1): transiciones, cobro, anulación, cancelación y WhatsApp.
class Api::V1::WorkOrdersFlowTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @owner   = users(:pro_co_owner)
    @manager = users(:pro_manager)
    @staff   = users(:pro_staff)
  end

  # --- Transiciones ---

  test "valid transitions walk an order from open to done and back" do
    order = work_orders(:pro_open)

    act(order, :start)
    assert_response :ok
    assert_equal "in_progress", json["status"]

    act(order, :finish)
    assert_response :ok
    assert_equal "done", json["status"]
    assert_not_nil json["completed_at"]

    act(order, :reopen)
    assert_response :ok
    assert_equal "in_progress", json["status"]
    assert_nil json["completed_at"]
  end

  test "invalid transitions answer 422 with from and action" do
    act(work_orders(:pro_paid), :start)
    assert_response :unprocessable_entity
    assert_equal({ "from" => "paid", "action" => "start" }, json.dig("error", "details"))

    act(work_orders(:pro_open), :reopen)
    assert_response :unprocessable_entity

    act(work_orders(:pro_open), :charge, payment_method: "card")
    assert_response :unprocessable_entity
    assert_equal "open", work_orders(:pro_open).reload.status
  end

  # --- Cobro ---

  test "charge in cash stores method, received and change" do
    order = work_orders(:pro_done)

    act(order, :charge, payment_method: "cash", amount_received: 1000)

    assert_response :ok
    assert_equal "paid", json["status"]
    ticket = json["ticket"]
    assert_equal "paid", ticket["status"]
    assert_equal "cash", ticket["payment_method"]
    assert_equal 850.0, ticket["amount_received"].to_f - ticket["change_given"].to_f
    assert_equal 150.0, ticket["change_given"].to_f
    assert_equal @owner.id, ticket.dig("charged_by", "id")
    assert ticket["folio"].present?
  end

  test "charge by card or transfer ignores the received amount" do
    act(work_orders(:pro_done), :charge, payment_method: "card", amount_received: 1)

    assert_response :ok
    assert_equal 850.0, json.dig("ticket", "amount_received").to_f
    assert_equal 0.0, json.dig("ticket", "change_given").to_f
  end

  test "insufficient cash answers 422 and saves nothing" do
    order = work_orders(:pro_done)

    act(order, :charge, payment_method: "cash", amount_received: 800)

    assert_response :unprocessable_entity
    assert_equal "50.0", json.dig("error", "details", "missing").to_s.sub(/\.0+\z/, ".0")
    assert_equal "done", order.reload.status
    assert_nil order.ticket
  end

  test "charge without priced items answers 422" do
    order = work_orders(:pro_unassigned)
    order.update!(status: :done)

    act(order, :charge, payment_method: "card")

    assert_response :unprocessable_entity
    assert_equal I18n.t("work_order.no_items"), json.dig("error", "message")
    assert_equal "done", order.reload.status
  end

  test "the total is recalculated when charging" do
    order = work_orders(:pro_done)
    order.work_order_items.create!(description: "Extra", quantity: 2, unit_price: 100, position: 1)
    order.update_column(:total, 1) # total desfasado a propósito

    act(order, :charge, payment_method: "card")

    assert_response :ok
    assert_equal 1050.0, json.dig("ticket", "total").to_f
    assert_equal 1050.0, order.reload.total.to_f
  end

  test "an invalid payment method answers 422" do
    act(work_orders(:pro_done), :charge, payment_method: "bitcoin")

    assert_response :unprocessable_entity
  end

  test "a paid order is locked" do
    order = work_orders(:pro_paid)

    put "/api/v1/work_orders/#{order.id}", params: { work_order: { title: "Otro" } }, headers: headers(@owner), as: :json
    assert_response :unprocessable_entity
    assert_equal "Lámparas de sala", order.reload.title

    post "/api/v1/work_orders/#{order.id}/items", params: { description: "Más", quantity: 1, unit_price: 10 },
         headers: headers(@owner), as: :json
    assert_response :unprocessable_entity
  end

  # --- Anulación ---

  test "void requires owner or admin and a reason" do
    order = work_orders(:pro_paid)

    act(order, :void_charge, { reason: "Error" }, as: @manager)
    assert_response :forbidden

    act(order, :void_charge, { reason: "Error" }, as: @staff)
    assert_includes [ 403, 404 ], response.status

    act(order, :void_charge)
    assert_response :unprocessable_entity
    assert_equal I18n.t("work_order.reason_required"), json.dig("error", "message")
    assert_equal "paid", order.reload.status
  end

  test "void leaves the ticket voided and the order done, and charging again keeps the folio" do
    order = work_orders(:pro_paid)
    folio = tickets(:pro_paid_ticket).folio

    act(order, :void_charge, reason: "Cobro duplicado")

    assert_response :ok
    assert_equal "done", json["status"]
    assert_equal "voided", json.dig("ticket", "status")
    assert_equal "Cobro duplicado", json.dig("ticket", "void_reason")
    assert_equal @owner.id, json.dig("ticket", "voided_by", "id")
    assert_not_nil json.dig("ticket", "voided_at")

    assert_no_difference "Ticket.count" do
      act(order, :charge, payment_method: "transfer")
    end
    assert_response :ok
    assert_equal "paid", json["status"]
    assert_equal folio, json.dig("ticket", "folio")
    assert_equal "paid", json.dig("ticket", "status")
    assert_nil json.dig("ticket", "voided_at")
  end

  # --- Cancelación ---

  test "cancel requires a reason and stores it" do
    order = work_orders(:pro_open)

    act(order, :cancel)
    assert_response :unprocessable_entity
    assert_equal "open", order.reload.status

    act(order, :cancel, reason: "El cliente se arrepintió")
    assert_response :ok
    assert_equal "cancelled", json["status"]
    assert_equal "El cliente se arrepintió", order.reload.cancel_reason
    event = json["events"].last
    assert_equal "cancelled", event["kind"]
    assert_equal "El cliente se arrepintió", event.dig("data", "reason")
  end

  test "staff cannot cancel" do
    act(work_orders(:pro_open), :cancel, { reason: "x" }, as: @staff)

    assert_response :forbidden
  end

  # --- WhatsApp ---

  test "send_whatsapp falls back to the customer phone of the order" do
    company = companies(:enterprise_co)
    owner = users(:enterprise_co_owner)
    order = company.work_orders.create!(title: "Con teléfono", created_by: owner, customer_phone: "5511112222")
    ticket = Ticket.create!(work_order: order, company: company)

    received = nil
    fake = Minitest::Mock.new
    fake.expect(:call, true)
    Whatsapp::TicketService.stub(:new, ->(t, phone:) { received = [ t.id, phone ]; fake }) do
      post "/api/v1/tickets/#{ticket.id}/send_whatsapp", headers: auth_headers(owner, company), as: :json
    end

    assert_response :ok
    assert_equal [ ticket.id, "5511112222" ], received
    fake.verify
  end

  test "send_whatsapp prefers the phone param over the order phone" do
    company = companies(:enterprise_co)
    owner = users(:enterprise_co_owner)
    order = company.work_orders.create!(title: "Con teléfono", created_by: owner, customer_phone: "5511112222")
    ticket = Ticket.create!(work_order: order, company: company)

    received = nil
    fake = Minitest::Mock.new
    fake.expect(:call, true)
    Whatsapp::TicketService.stub(:new, ->(_t, phone:) { received = phone; fake }) do
      post "/api/v1/tickets/#{ticket.id}/send_whatsapp", params: { phone: "5599998888" },
           headers: auth_headers(owner, company), as: :json
    end

    assert_response :ok
    assert_equal "5599998888", received
  end

  private

  def headers(user)
    auth_headers(user, @company)
  end

  # --- spec 015: cobro con varios pagos ---

  test "a mixed charge creates one payment per method and a mixed ticket" do
    order = work_orders(:pro_done)
    act(order, :charge, payments: [ { method: "card", amount: 300, terminal_id: payment_terminals(:pro_bbva).id, authorization_code: "123456" },
                                    { method: "cash", amount_received: 600 } ])
    assert_response :ok
    ticket = json["ticket"]
    assert_equal "mixed", ticket["payment_method"]
    assert_equal "50.0", ticket["change_given"].to_s
    assert_equal [ %w[card 300.00], %w[cash 550.00] ], ticket["payments"].map { |p| [ p["method"], p["amount"] ] }
    card = ticket["payments"].first
    assert_equal({ "id" => payment_terminals(:pro_bbva).id, "name" => "BBVA caja 1", "provider" => "bbva" }, card["terminal"])
    assert_equal "123456", card["authorization_code"]
    assert_equal "manual", card["source"]
    charged = json["events"].find { |e| e["kind"] == "charged" }
    assert_equal [ { "method" => "card", "amount" => "300.0" }, { "method" => "cash", "amount" => "550.0" } ], charged.dig("data", "payments")
  end

  test "a repeated Idempotency-Key does not charge twice and a second charge is rejected" do
    order = work_orders(:pro_done)
    body = { payments: [ { method: "card", amount: 850 } ] }
    key = { "Idempotency-Key" => "cobro-#{order.id}" }
    2.times do
      post "/api/v1/work_orders/#{order.id}/charge", params: body, headers: headers(@owner).merge(key), as: :json
      assert_response :ok
    end
    assert_equal 1, order.reload.ticket.ticket_payments.count

    act(order, :charge, body)
    assert_response :unprocessable_entity
    assert_equal 1, order.reload.ticket.ticket_payments.count
  end

  test "an invalid payment list answers 422 with its code and charges nothing" do
    order = work_orders(:pro_done)
    act(order, :charge, payments: [ { method: "card", amount: 900 } ])
    assert_response :unprocessable_entity
    assert_equal "exceeds_total", json.dig("error", "details", "code")
    assert order.reload.done?
    assert_nil order.ticket
  end

  test "voiding keeps the payments voided in the history and charging again adds new ones" do
    order = work_orders(:pro_paid)
    act(order, :void_charge, reason: "Error de captura")
    assert_response :ok
    payment = ticket_payments(:pro_paid_card).reload
    assert_not_nil payment.voided_at
    voided = json["events"].find { |e| e["kind"] == "voided" }
    assert_equal [ { "method" => "card", "amount" => "500.0" } ], voided.dig("data", "payments")

    act(order, :charge, payments: [ { method: "cash", amount_received: 500 } ])
    assert_response :ok
    assert_equal tickets(:pro_paid_ticket).folio, json.dig("ticket", "folio")
    assert_equal 2, json.dig("ticket", "payments").size
    assert_equal 1, json.dig("ticket", "payments").count { |p| p["voided_at"].nil? }
  end

  test "staff charges their own order with several payments" do
    order = work_orders(:pro_open)
    act(order, :finish, as: @staff)
    act(order, :charge, { payments: [ { method: "transfer", amount: 100, reference: "SPEI 1" }, { method: "cash", amount_received: 500 } ] }, as: @staff)
    assert_response :ok
    assert_equal @staff.id, json.dig("ticket", "payments", 0, "created_by", "id")
  end

  def act(order, action, params = {}, as: @owner, **extra)
    params = params.merge(extra)
    post "/api/v1/work_orders/#{order.id}/#{action}", params: params, headers: headers(as), as: :json
  end

  def json
    response.parsed_body
  end

  test "order items return the product icons" do
    products(:one).update!(icon: "plug")
    products(:one).product_type.update!(icon: "gear")

    get "/api/v1/work_orders/#{work_orders(:pro_open).id}", headers: auth_headers(@owner, @company)

    assert_response :ok
    product = response.parsed_body["items"].filter_map { |i| i["product"] }.first
    assert_equal "plug", product["icon"]
    assert_equal "gear", product["type_icon"]
  end
end
