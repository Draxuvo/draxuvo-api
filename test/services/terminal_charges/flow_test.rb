require "test_helper"

# Spec 069, US1 (quickstart §1): crear, sincronizar, aplicar y cancelar solicitudes de cobro en terminal integrada.
class TerminalCharges::FlowTest < ActiveSupport::TestCase
  setup do
    @pro = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @terminal = integrated_terminal(@pro)
    @order = work_orders(:pro_done) # terminada, $850
  end

  def create(company: @pro, user: @owner, **params)
    TerminalCharges::Create.call(company: company, user: user, params: params)
  end

  def approve!(charge, fake)
    fake.charge_status = "approved"
    fake.charge_detail = "accredited"
    TerminalCharges::Sync.call(charge.reload)
    charge.reload
  end

  test "orden de trabajo mixta: aprobada registra los dos pagos con el de terminal confirmado" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "500", work_order_id: @order.id,
                      params: { payments: [ { method: "cash", amount_received: "350" } ] })
      assert charge.pending?
      assert_equal "ORD#{charge.id}", charge.provider_order_id
      assert_equal BigDecimal("500"), fake.calls_of(:create_charge).sole[:amount]
      assert_equal "done", @order.reload.status, "la validación previa no debe cobrar"

      charge = approve!(charge, fake)
      assert charge.applied?, charge.unapplied_reason
      assert_equal "paid", @order.reload.status
      payments = @order.ticket.ticket_payments.order(:id)
      assert_equal %w[cash card], payments.map(&:payment_method)
      card = payments.find(&:card?)
      assert card.terminal?
      assert_equal charge.id, card.terminal_charge_id
      assert_equal "123456789", card.reference
      assert_equal "4242", card.card_last4
      assert_equal card.id, charge.ticket_payment_id
      assert_equal [], charge.params.dig("result", "stock_shortages")
    end
  end

  test "rechazada no registra nada y la orden sigue por cobrar" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      fake.charge_status = "declined"
      fake.charge_detail = "rejected_by_issuer"
      TerminalCharges::Sync.call(charge)
      assert_equal "declined", charge.reload.status
      assert_equal "rejected_by_issuer", charge.status_detail
      assert_equal "done", @order.reload.status
      assert_nil @order.ticket
    end
  end

  test "un aviso repetido y el barrido a la vez aplican una sola vez" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      fake.charge_status = "approved"
      3.times { TerminalCharges::Sync.call(TerminalCharge.find(charge.id)) }
      assert_equal 1, TicketPayment.where(terminal_charge_id: charge.id).count
      assert TerminalCharge.find(charge.id).applied?
    end
  end

  test "la terminal ocupada y el cobro con solicitud abierta dan 409" do
    with_fake_provider do
      create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      error = assert_raises(ApiErrors::BaseError) { create(terminal_id: @terminal.id, amount: "100", work_order_id: work_orders(:pro_open).id) }
      assert_equal "terminal_busy", error.details[:code]
      other = integrated_terminal(@pro)
      error = assert_raises(ApiErrors::BaseError) { create(terminal_id: other.id, amount: "850", work_order_id: @order.id) }
      assert_equal "terminal_charge_pending", error.details[:code]
    end
  end

  test "un error del reparto sale antes de mandar a la terminal" do
    with_fake_provider do |fake|
      error = assert_raises(ApiErrors::UnprocessableEntityError) { create(terminal_id: @terminal.id, amount: "100", work_order_id: @order.id) }
      assert_equal "missing", error.details[:code]
      assert_empty fake.calls_of(:create_charge)
      assert_equal 0, TerminalCharge.count
    end
  end

  test "solo un pago integrado por cobro" do
    other = integrated_terminal(@pro)
    with_fake_provider do
      error = assert_raises(ApiErrors::UnprocessableEntityError) do
        create(terminal_id: @terminal.id, amount: "500", work_order_id: @order.id,
               params: { payments: [ { method: "card", amount: "350", terminal_id: other.id } ] })
      end
      assert_equal "one_integrated_payment", error.details[:code]
    end
  end

  test "una terminal manual o con la conexión en error no recibe cobros" do
    with_fake_provider do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { create(terminal_id: payment_terminals(:pro_bbva).id, amount: "850", work_order_id: @order.id) }
      assert_equal "terminal_not_chargeable", error.details[:code]
      @terminal.terminal_connection.update!(status: "error")
      error = assert_raises(ApiErrors::UnprocessableEntityError) { create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id) }
      assert_equal "terminal_not_chargeable", error.details[:code]
    end
  end

  test "con cobro solo por jefes el personal no crea solicitudes (spec 058)" do
    @pro.update!(boss_only_charge: true)
    staff = users(:pro_staff)
    employee = @pro.employees.find_by(user_id: staff.id) || @pro.employees.create!(name: "Staff", user: staff, salary: 1000)
    @order.update!(employee: employee)
    with_fake_provider do
      error = assert_raises(ApiErrors::ForbiddenError) { create(user: staff, terminal_id: @terminal.id, amount: "850", work_order_id: @order.id) }
      assert_equal "charge_boss_only", error.details[:code]
    end
  end

  test "si el proveedor no responde al crear no queda nada pendiente" do
    with_fake_provider do |fake|
      fake.create_error = provider_error(:transient, "provider_unavailable")
      error = assert_raises(ApiErrors::BaseError) { create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id) }
      assert_equal "provider_unavailable", error.details[:code]
      charge = TerminalCharge.sole
      assert_equal "declined", charge.status
      assert_not @terminal.reload.open_charge
    end
  end

  test "cancelar: recién creada se cancela; en la terminal queda cancelando; procesándose da 409" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      TerminalCharges::Cancel.call(charge, user: @owner)
      assert_equal "canceled", charge.reload.status

      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      fake.cancel_result = :requested
      TerminalCharges::Cancel.call(charge, user: @owner)
      assert_equal "canceling", charge.reload.status
      fake.charge_status = "canceled"
      fake.charge_detail = "canceled_by_api"
      TerminalCharges::Sync.call(charge)
      assert_equal "canceled", charge.reload.status

      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      fake.cancel_result = :not_cancelable
      error = assert_raises(ApiErrors::BaseError) { TerminalCharges::Cancel.call(charge, user: @owner) }
      assert_equal "not_cancelable", error.details[:code]
    end
  end

  test "una aprobación cuando la orden ya se cobró por otra vía queda sin aplicar" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      TerminalCharges::Abandon.call(charge, user: @owner)
      WorkOrders::Transition.call(@order.reload, :charge, WorkOrders::Transition::Context.new(user: @owner, role: "owner"),
                                  { payments: [ { method: "card", amount: "850", terminal_id: @terminal.id } ] })
      manual = @order.reload.ticket.ticket_payments.sole
      assert manual.manual?

      charge = approve!(charge, fake)
      assert charge.unapplied?
      assert_equal "already_paid", charge.unapplied_reason
      assert_equal 1, @order.ticket.ticket_payments.count
    end
  end

  test "una abandonada que se aprueba sin cobro a mano se aplica" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      TerminalCharges::Abandon.call(charge, user: @owner)
      charge = approve!(charge, fake)
      assert charge.applied?
      assert_equal "paid", @order.reload.status
    end
  end

  test "vencida sin respuesta del proveedor se da por vencida" do
    with_fake_provider do |fake|
      charge = create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id)
      charge.update_columns(expires_at: 10.minutes.ago)
      fake.charge_status = "pending"
      TerminalCharges::Sync.call(charge.reload)
      assert_equal "expired", charge.reload.status
      assert fake.calls_of(:cancel_charge).any?
    end
  end

  test "venta de mostrador: aprobada cobra la venta y descuenta inventario" do
    company = companies(:pos_co)
    company.subscription.update!(plan: :pro)
    cashier = users(:pos_owner)
    terminal = integrated_terminal(company)
    sale = open_sale(cashier, [ products(:pos_cuaderno), 2 ], company: company)
    with_fake_provider do |fake|
      charge = create(company: company, user: cashier, terminal_id: terminal.id, amount: sale.total.to_s, sale_id: sale.id,
                      params: { lock_version: sale.lock_version })
      error = assert_raises(ApiErrors::UnprocessableEntityError) { TerminalCharge.ensure_none_open!(sale) }
      assert_equal "terminal_charge_pending", error.details[:code]
      charge = approve!(charge, fake)
      assert charge.applied?, charge.unapplied_reason
      assert sale.reload.status_paid?
      assert sale.ticket.ticket_payments.sole.terminal?
      assert_equal 16, products(:pos_cuaderno).reload.stock
    end
  end

  test "cuenta de mesa: el abono aprobado cierra la cuenta" do
    company = companies(:resto_co)
    check = settle_check(checks(:open_check))
    terminal = integrated_terminal(company)
    waiter = users(:resto_waiter)
    with_fake_provider do |fake|
      charge = create(company: company, user: waiter, terminal_id: terminal.id, amount: check.balance.to_s, check_id: check.id)
      error = assert_raises(ApiErrors::UnprocessableEntityError) do
        Restaurant::AddPayment.call(check, Restaurant::Permissions::Context.new(user: waiter, role: "staff", company: company),
                                    { method: "cash", amount: "10", amount_received: "10" })
      end
      assert_equal "terminal_charge_pending", error.details[:code]

      charge = approve!(charge, fake)
      assert charge.applied?, charge.unapplied_reason
      assert check.reload.status_closed?
      payment = check.check_payments.sole
      assert payment.terminal?
      assert_equal payment.id, charge.check_payment_id
    end
  end

  test "en una demo no se crean solicitudes" do
    as_demo do
      assert_raises(Demo::Restricted) { create(terminal_id: @terminal.id, amount: "850", work_order_id: @order.id) }
    end
  end
end
