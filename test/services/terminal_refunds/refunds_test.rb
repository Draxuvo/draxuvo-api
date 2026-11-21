require "test_helper"

# Spec 069, US6 (FR-031 a FR-037, research R8): reembolsos al anular un cobro integrado y de pagos sin aplicar.
class TerminalRefunds::RefundsTest < ActiveSupport::TestCase
  setup do
    @pro = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @terminal = integrated_terminal(@pro)
    @order = work_orders(:pro_done) # terminada, $850
  end

  def context(user = @owner, role = "owner") = WorkOrders::Transition::Context.new(user: user, role: role)

  # Cobra la orden con $500 en la terminal integrada y $350 en efectivo; devuelve la solicitud aplicada.
  def charge_order!(fake)
    charge = TerminalCharges::Create.call(company: @pro, user: @owner,
                                          params: { terminal_id: @terminal.id, amount: "500", work_order_id: @order.id,
                                                    params: { payments: [ { method: "cash", amount_received: "350" } ] } })
    fake.charge_status = "approved"
    TerminalCharges::Sync.call(charge.reload)
    charge.reload.tap { |applied| assert applied.applied?, applied.unapplied_reason }
  end

  def void!(refund: nil, user: @owner, role: "owner")
    WorkOrders::Transition.call(@order.reload, :void_charge, context(user, role), { reason: "Cliente devolvió", refund: refund }.compact)
  end

  test "sin confirmar pide confirmación con monto y terminal y no anula" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      error = assert_raises(ApiErrors::UnprocessableEntityError) { void! }
      assert_equal "refund_confirmation_required", error.details[:code]
      refund = error.details[:refunds].sole
      assert_equal "500.00", refund[:amount]
      assert_equal charge.ticket_payment_id, refund[:ticket_payment_id]
      assert_equal @terminal.name, refund[:terminal][:name]
      assert_equal "paid", @order.reload.status
      assert_empty fake.calls_of(:refund)
    end
  end

  test "confirmar reembolsa y anula; la solicitud queda reembolsada y el pago con su reembolso" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      void!(refund: "confirm")
      assert_equal "done", @order.reload.status
      assert_equal "voided", @order.ticket.status
      assert_equal "refund-#{charge.id}-1", fake.calls_of(:refund).sole[:idempotency_key]
      refund = charge.reload.terminal_refund
      assert refund.done?
      assert_equal "REF01", refund.provider_refund_id
      assert_equal BigDecimal("500"), refund.amount
      assert_equal "refunded", charge.status
      assert_equal charge.ticket_payment_id, refund.ticket_payment_id

      payments = TicketSerializer.new(@order.ticket, detailed: true).as_json[:voids].sole[:payments]
      card = payments.find { |payment| payment["ticket_payment_id"] }
      assert_equal "done", card["refund"][:status]
      json = TicketSerializer.payment_json(TicketPayment.find(charge.ticket_payment_id))
      assert_equal "terminal", json[:source]
      assert_equal "done", json[:refund][:status]
    end
  end

  test "si el proveedor rechaza no anula y el siguiente intento usa otra llave" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      fake.refund_error = provider_error(:declined, "refund_period_exceeded", http_status: 400)
      error = assert_raises(ApiErrors::UnprocessableEntityError) { void!(refund: "confirm") }
      assert_equal "refund_failed", error.details[:code]
      assert_equal "refund_period_exceeded", error.details[:reason]
      assert_equal "paid", @order.reload.status
      assert charge.reload.terminal_refund.rejected?

      fake.refund_error = nil
      void!(refund: "confirm")
      assert_equal %W[refund-#{charge.id}-1 refund-#{charge.id}-2], fake.calls_of(:refund).map { |call| call[:idempotency_key] }
      assert_equal "done", @order.reload.status
    end
  end

  test "sin respuesta del proveedor el reintento reutiliza la llave" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      fake.refund_error = provider_error(:transient, "provider_unavailable")
      error = assert_raises(ApiErrors::UnprocessableEntityError) { void!(refund: "confirm") }
      assert_equal "provider_unavailable", error.details[:reason]
      assert charge.reload.terminal_refund.requested?

      fake.refund_error = nil
      void!(refund: "confirm")
      assert_equal [ "refund-#{charge.id}-1" ] * 2, fake.calls_of(:refund).map { |call| call[:idempotency_key] }
    end
  end

  test "anular sin reembolso deja el pago pendiente fuera de Draxuvo" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      void!(refund: "skip")
      assert_equal "done", @order.reload.status
      assert charge.reload.terminal_refund.skipped?
      assert_equal "applied", charge.status
      assert_empty fake.calls_of(:refund)
    end
  end

  test "con la conexión en error no se pide el reembolso" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      @terminal.terminal_connection.update!(status: "error")
      error = assert_raises(ApiErrors::UnprocessableEntityError) { void!(refund: "confirm") }
      assert_equal "connection_error", error.details[:reason]
      assert_nil charge.reload.terminal_refund
      assert_empty fake.calls_of(:refund)
    end
  end

  test "volver a cobrar y anular reembolsa solo el pago nuevo" do
    with_fake_provider do |fake|
      first = charge_order!(fake)
      void!(refund: "confirm")
      fake.charge_status = "pending"
      second = charge_order!(fake)
      void!(refund: "confirm")
      assert_equal [ first.id, second.id ], fake.calls_of(:refund).map { |call| call[:charge_id] }
      assert second.reload.terminal_refund.done?
    end
  end

  test "un reembolso en proceso lo da por hecho la sincronización" do
    with_fake_provider do |fake|
      charge = charge_order!(fake)
      fake.refund_result = TerminalProviders::ProviderRefund.new(id: "REF02", status: "requested")
      void!(refund: "confirm")
      refund = charge.reload.terminal_refund
      assert refund.requested?
      charge.update_columns(last_synced_at: 1.minute.ago)
      assert_includes TerminalCharge.due_for_sync, charge

      fake.charge_status = "refunded"
      TerminalCharges::Sync.call(charge.reload)
      assert refund.reload.done?
      assert_equal "refunded", charge.reload.status
    end
  end

  test "un pago registrado a mano se anula como hoy, sin reembolso" do
    WorkOrders::Transition.call(@order, :charge, context, { payments: [ { method: "card", amount: "850", terminal_id: @terminal.id } ] })
    with_fake_provider do |fake|
      void!
      assert_equal "done", @order.reload.status
      assert_empty fake.calls_of(:refund)
    end
  end

  test "el personal no anula un cobro integrado" do
    with_fake_provider do |fake|
      charge_order!(fake)
      assert_raises(ApiErrors::ForbiddenError) { void!(refund: "confirm", user: users(:pro_staff), role: "staff") }
      assert_empty fake.calls_of(:refund)
    end
  end

  test "venta cancelada con reembolso devuelve el inventario como hoy" do
    company = companies(:pos_co)
    company.subscription.update!(plan: :pro)
    cashier = users(:pos_owner)
    terminal = integrated_terminal(company)
    sale = open_sale(cashier, [ products(:pos_cuaderno), 2 ], company: company)
    with_fake_provider do |fake|
      charge = TerminalCharges::Create.call(company: company, user: cashier,
                                            params: { terminal_id: terminal.id, amount: sale.total.to_s, sale_id: sale.id,
                                                      params: { lock_version: sale.lock_version } })
      fake.charge_status = "approved"
      TerminalCharges::Sync.call(charge.reload)
      assert_equal 16, products(:pos_cuaderno).reload.stock

      error = assert_raises(ApiErrors::UnprocessableEntityError) { Sales::Cancel.call(sale.reload, cashier, "Devolución") }
      assert_equal "refund_confirmation_required", error.details[:code]
      assert sale.reload.status_paid?

      Sales::Cancel.call(sale, cashier, "Devolución", "confirm")
      assert sale.reload.status_cancelled?
      assert_equal 18, products(:pos_cuaderno).reload.stock
      assert charge.reload.terminal_refund.done?
    end
  end

  test "un pago sin aplicar se reembolsa una sola vez o se marca atendido" do
    with_fake_provider do |fake|
      charge = TerminalCharges::Create.call(company: @pro, user: @owner,
                                            params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id })
      TerminalCharges::Abandon.call(charge, user: @owner)
      WorkOrders::Transition.call(@order.reload, :charge, context, { payments: [ { method: "cash", amount_received: "850" } ] })
      fake.charge_status = "approved"
      TerminalCharges::Sync.call(charge.reload)
      assert charge.reload.unapplied?
      assert_includes TerminalCharge.unapplied_pending, charge

      TerminalRefunds::Request.call(charge, user: @owner)
      assert_equal "refunded", charge.reload.status
      assert_not_includes TerminalCharge.unapplied_pending, charge
      error = assert_raises(ApiErrors::BaseError) { TerminalRefunds::Request.call(charge, user: @owner) }
      assert_equal "already_refunded", error.details[:code]
      assert_equal 1, fake.calls_of(:refund).size
    end
  end
end
