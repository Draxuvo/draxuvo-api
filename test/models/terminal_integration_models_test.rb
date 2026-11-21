require "test_helper"

# Spec 069 (data-model.md): conexiones, terminales integradas, solicitudes, reembolsos y bitácora.
class TerminalIntegrationModelsTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
  end

  test "la conexión cifra sus tokens y nunca los serializa" do
    connection = terminal_connection_for(@company)
    raw = TerminalConnection.connection.select_value("SELECT access_token FROM terminal_connections WHERE id = #{connection.id}")
    assert_not_includes raw, "APP_USR-token"
    assert_equal "APP_USR-token", connection.reload.token
    json = connection.as_json
    assert_not json.key?("access_token")
    assert_not json.key?("refresh_token")
    assert_not_includes connection.inspect, "APP_USR"
  end

  test "una conexión por proveedor y empresa; otra empresa puede usar la misma cuenta" do
    terminal_connection_for(@company)
    duplicate = TerminalConnection.new(company: @company, provider: "mercado_pago", status: "connected")
    assert_not duplicate.valid?
    other = terminal_connection_for(companies(:enterprise_co), account_id: "1001")
    assert other.persisted?
  end

  test "desconectar borra tokens y conserva la fila" do
    connection = terminal_connection_for(@company)
    connection.disconnect!
    connection.reload
    assert connection.disconnected?
    assert_nil connection.token
    assert_nil connection.renewal_token
  end

  test "una terminal integrada es chargeable solo activa y con conexión al corriente" do
    terminal = integrated_terminal(@company)
    assert terminal.integrated?
    assert_equal "integrated", terminal.kind
    assert terminal.chargeable?
    terminal.terminal_connection.update!(status: "error")
    assert_not terminal.reload.chargeable?
    assert_equal "manual", payment_terminals(:pro_bbva).kind
    assert_not payment_terminals(:pro_bbva).chargeable?
  end

  test "un dispositivo solo puede ligarse una vez en toda la plataforma" do
    terminal = integrated_terminal(@company)
    other = companies(:enterprise_co).payment_terminals.new(name: "Otra", provider: "mercado_pago", device_id: terminal.device_id,
                                                              terminal_connection: terminal_connection_for(companies(:enterprise_co)))
    assert_not other.valid?
    assert other.errors.key?(:device_id)
  end

  test "una integrada no cambia de proveedor" do
    terminal = integrated_terminal(@company)
    assert_not terminal.update(provider: "clip")
    assert terminal.errors.key?(:provider)
  end

  test "la solicitud exige exactamente un dueño y monto positivo" do
    terminal = integrated_terminal(@company)
    base = { company: @company, payment_terminal: terminal, terminal_connection: terminal.terminal_connection, created_by: @owner }
    assert_not TerminalCharge.new(base.merge(amount: 10)).valid?
    assert_not TerminalCharge.new(base.merge(amount: 0, work_order: work_orders(:pro_done))).valid?
    both = TerminalCharge.new(base.merge(amount: 10, work_order: work_orders(:pro_done), check: checks(:open_check)))
    assert_not both.valid?
    charge = TerminalCharge.create!(base.merge(amount: 10, work_order: work_orders(:pro_done)))
    assert_match(/\Adx-#{@company.id}-/, charge.external_reference)
    assert charge.external_reference.length <= 64
    assert charge.idempotency_key.present?
    assert_in_delta 3.minutes.from_now, charge.expires_at, 5
    assert_equal "work_order", charge.owner_type
  end

  test "una terminal y un dueño solo tienen una solicitud abierta" do
    terminal = integrated_terminal(@company)
    base = { company: @company, payment_terminal: terminal, terminal_connection: terminal.terminal_connection, created_by: @owner, amount: 10 }
    TerminalCharge.create!(base.merge(work_order: work_orders(:pro_done)))
    assert_raises(ActiveRecord::RecordNotUnique) { TerminalCharge.create!(base.merge(work_order: work_orders(:pro_open))) }
    other_terminal = integrated_terminal(@company)
    assert_raises(ActiveRecord::RecordNotUnique) do
      TerminalCharge.create!(base.merge(payment_terminal: other_terminal, work_order: work_orders(:pro_done)))
    end
  end

  test "no se desactiva ni se borra una terminal con solicitud abierta" do
    terminal = integrated_terminal(@company)
    TerminalCharge.create!(company: @company, payment_terminal: terminal, terminal_connection: terminal.terminal_connection,
                           created_by: @owner, amount: 10, work_order: work_orders(:pro_done))
    assert_not terminal.update(active: false)
    assert_not terminal.destroy
  end

  test "un pago con origen terminal exige tarjeta, terminal y solicitud" do
    payment = TicketPayment.new(source: :terminal, payment_method: :cash, amount: 10)
    payment.valid?
    assert payment.errors.key?(:source)
  end

  test "el reembolso cambia de llave solo en un nuevo intento" do
    terminal = integrated_terminal(@company)
    charge = TerminalCharge.create!(company: @company, payment_terminal: terminal, terminal_connection: terminal.terminal_connection,
                                    created_by: @owner, amount: 10, work_order: work_orders(:pro_done), status: "unapplied")
    refund = TerminalRefund.create!(company: @company, terminal_charge: charge, amount: 10, status: "requested", requested_by: @owner)
    assert_equal "refund-#{charge.id}-1", refund.idempotency_key
    refund.update!(status: "rejected")
    refund.next_attempt!
    assert_equal "refund-#{charge.id}-2", refund.idempotency_key
    assert refund.requested?
  end

  test "la bitácora es de solo inserción y no guarda secretos" do
    event = TerminalEvent.log!(:connected, company: @company, access_token: "x", nested: { refresh_token: "y", ok: 1 })
    assert_equal({ "nested" => { "ok" => 1 } }, event.data)
    assert event.readonly?
  end
end
