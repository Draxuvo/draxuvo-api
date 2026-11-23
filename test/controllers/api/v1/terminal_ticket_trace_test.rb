require "test_helper"

# Spec 069, US5 (T075): Reportes «Por terminal» suma lo cobrado por la terminal integrada y lo registrado a mano en la
# misma terminal, y el ticket dice el origen de cada pago con la referencia del proveedor (también en «Anulaciones previas»).
class Api::V1::TerminalTicketTraceTest < ActionDispatch::IntegrationTest
  setup do
    @pro = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @headers = auth_headers(@owner, @pro)
    @terminal = integrated_terminal(@pro)
    @order = work_orders(:pro_done) # terminada, $850
  end

  # Cobra la orden con $500 en la terminal integrada y $350 en efectivo.
  def charge_order!(fake)
    charge = TerminalCharges::Create.call(company: @pro, user: @owner,
                                          params: { terminal_id: @terminal.id, amount: "500", work_order_id: @order.id,
                                                    params: { payments: [ { method: "cash", amount_received: "350" } ] } })
    fake.charge_status = "approved"
    TerminalCharges::Sync.call(charge.reload)
    charge.reload.tap { |applied| assert applied.applied?, applied.unapplied_reason }
  end

  # Otro ticket pagado hoy con tarjeta registrada a mano en la misma terminal.
  def manual_card_ticket!(amount)
    order = WorkOrder.create!(company: @pro, created_by: @owner, title: "Registro a mano", total: amount)
    ticket = Ticket.create!(work_order: order, company: @pro, total: amount, status: :paid, payment_method: :card, amount_received: amount,
                            charged_by: @owner, paid_at: Time.current)
    ticket.ticket_payments.create!(company: @pro, payment_method: :card, amount: amount, terminal: @terminal,
                                   created_by: @owner, reference: "VOUCHER-7")
    ticket
  end

  test "Reportes «Por terminal» suma el cobro integrado y el registrado a mano en la misma terminal" do
    with_fake_provider do |fake|
      charge_order!(fake)
      manual_card_ticket!(200)

      today = Time.zone.today.iso8601
      get "/api/v1/reports/income", params: { from: today, to: today }, headers: @headers

      assert_response :ok
      row = response.parsed_body["by_terminal"].find { |entry| entry.dig("terminal", "id") == @terminal.id }
      assert_equal 700.0, row["total"]
      assert_equal 2, row["count"]
    end
  end

  test "el detalle del ticket marca el pago integrado con su referencia y el manual como registrado a mano" do
    with_fake_provider do |fake|
      charge_order!(fake)
      get "/api/v1/tickets/#{@order.reload.ticket.id}", headers: @headers
      assert_response :ok
      card = response.parsed_body["payments"].find { |payment| payment["method"] == "card" }
      cash = response.parsed_body["payments"].find { |payment| payment["method"] == "cash" }
      assert_equal "terminal", card["source"]
      assert_equal "123456789", card["provider_reference"]
      assert_equal @terminal.id, card.dig("terminal", "id")
      assert_nil card["refund"]
      assert_equal "manual", cash["source"]
      assert_nil cash["provider_reference"]
    end

    ticket = manual_card_ticket!(200)
    get "/api/v1/tickets/#{ticket.id}", headers: @headers
    payment = response.parsed_body["payments"].sole
    assert_equal "manual", payment["source"]
    assert_equal "VOUCHER-7", payment["reference"]
    assert_nil payment["provider_reference"]
  end

  test "«Anulaciones previas» conserva el origen, la referencia y el reembolso del pago integrado" do
    with_fake_provider do |fake|
      charge_order!(fake)
      context = WorkOrders::Transition::Context.new(user: @owner, role: "owner")
      WorkOrders::Transition.call(@order.reload, :void_charge, context, { reason: "Cliente devolvió", refund: "confirm" })

      get "/api/v1/tickets/#{@order.reload.ticket.id}", headers: @headers
      assert_response :ok
      payments = response.parsed_body["voids"].sole["payments"]
      card = payments.find { |payment| payment["method"] == "card" }
      cash = payments.find { |payment| payment["method"] == "cash" }
      assert_equal "terminal", card["source"]
      assert_equal "123456789", card["provider_reference"]
      assert_equal @terminal.name, card.dig("terminal", "name")
      assert_equal "done", card.dig("refund", "status")
      assert_nil cash["source"]
    end
  end
end
