require "test_helper"

# Spec 069, research R1 y R10: el adaptador de Mercado Pago Point con respuestas grabadas (Net::HTTP simulado).
class TerminalProviders::MercadoPagoTest < ActiveSupport::TestCase
  FakeHttp = Struct.new(:responses, :requests, :error) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      raise error if error

      responses.shift
    end
  end

  def http_response(code, body)
    klass = Net::HTTPResponse::CODE_TO_OBJ[code.to_s] || Net::HTTPResponse
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
    end
  end

  def run_with(*responses, error: nil)
    http = FakeHttp.new(responses.map { |code, body| http_response(code, body) }, [], error)
    result = nil
    Net::HTTP.stub(:new, ->(*) { http }) { result = yield TerminalProviders::MercadoPago.new }
    [ result, http ]
  end

  def order(status:, detail: status, payment_status: status, payment_detail: detail, extra: {})
    { "id" => "ORD01", "status" => status, "status_detail" => detail,
      "transactions" => { "payments" => [ { "id" => "PAY01", "amount" => "350.00", "status" => payment_status,
                                            "status_detail" => payment_detail, "reference_id" => "987654",
                                            "payment_method" => { "type" => "credit_card", "id" => "visa" } } ] } }.merge(extra)
  end

  setup do
    @company = companies(:pro_co)
    @terminal = integrated_terminal(@company)
    @charge = TerminalCharge.create!(company: @company, payment_terminal: @terminal, terminal_connection: @terminal.terminal_connection,
                                     created_by: users(:pro_co_owner), amount: BigDecimal("350"), work_order: work_orders(:pro_done))
  end

  test "crear cobro manda la orden de Point con idempotencia, monto como texto y 3 minutos" do
    result, http = run_with([ 201, order(status: "created") ]) { |mp| mp.create_charge(@charge) }
    request = http.requests.sole
    body = JSON.parse(request.body)
    assert_equal "/v1/orders", request.path
    assert_equal "Bearer APP_USR-token", request["Authorization"]
    assert_equal @charge.idempotency_key, request["X-Idempotency-Key"]
    assert_equal "point", body["type"]
    assert_equal "350.00", body.dig("transactions", "payments", 0, "amount")
    assert_equal @terminal.device_id, body.dig("config", "point", "terminal_id")
    assert_equal "PT3M", body["expiration_time"]
    assert_equal @charge.external_reference, body["external_reference"]
    assert_equal "ORD01", result.id
    assert_equal "PAY01", result.payment_id
    assert_equal "pending", result.status
  end

  test "traduce los estados de la orden" do
    {
      order(status: "at_terminal") => %w[pending at_terminal],
      order(status: "processed", payment_detail: "accredited") => %w[approved accredited],
      order(status: "failed", payment_detail: "rejected_by_issuer") => %w[declined rejected_by_issuer],
      order(status: "canceled", payment_detail: "canceled_on_terminal") => %w[canceled canceled_on_terminal],
      order(status: "expired") => %w[expired expired],
      order(status: "action_required") => %w[declined check_on_terminal],
      order(status: "processed", detail: "partially_refunded") => %w[refunded accredited].first(1)
    }.each do |raw, (status, detail)|
      @charge.update_columns(provider_order_id: "ORD01")
      result, = run_with([ 200, raw ]) { |mp| mp.fetch_charge(@charge) }
      assert_equal status, result.status, raw.inspect
      assert_equal detail, result.detail, raw.inspect if detail
    end
  end

  test "la referencia del pago aprobado" do
    @charge.update_columns(provider_order_id: "ORD01")
    result, = run_with([ 200, order(status: "processed") ]) { |mp| mp.fetch_charge(@charge) }
    assert_equal "987654", result.reference
    assert_equal "credit_card", result.payment_type
  end

  test "cancelar una orden en la terminal manda el encabezado y queda en proceso" do
    @charge.update_columns(provider_order_id: "ORD01")
    result, http = run_with([ 200, order(status: "at_terminal") ], [ 202, order(status: "at_terminal") ]) { |mp| mp.cancel_charge(@charge) }
    assert_equal :requested, result
    cancel = http.requests.last
    assert_equal "/v1/orders/ORD01/cancel", cancel.path
    assert_equal "at_terminal", cancel["x-allow-cancelable-status"]
    assert cancel["X-Idempotency-Key"].present?
  end

  test "cancelar una orden recién creada es inmediato y una en proceso no se puede" do
    @charge.update_columns(provider_order_id: "ORD01")
    result, = run_with([ 200, order(status: "created") ], [ 200, order(status: "canceled") ]) { |mp| mp.cancel_charge(@charge) }
    assert_equal :canceled, result
    result, = run_with([ 200, order(status: "at_terminal") ], [ 409, { "errors" => [ { "code" => "cannot_cancel_order" } ] } ]) { |mp| mp.cancel_charge(@charge) }
    assert_equal :not_cancelable, result
  end

  test "reembolsar usa la llave que se le da" do
    @charge.update_columns(provider_order_id: "ORD01")
    body = order(status: "refunded").merge("transactions" => { "refunds" => [ { "id" => "REF01", "status" => "processed" } ] })
    result, http = run_with([ 201, body ]) { |mp| mp.refund(@charge, idempotency_key: "refund-1-1") }
    assert_equal "refund-1-1", http.requests.sole["X-Idempotency-Key"]
    assert_equal "/v1/orders/ORD01/refund", http.requests.sole.path
    assert_equal "done", result.status
    assert_equal "REF01", result.id
  end

  test "clasifica los errores" do
    @charge.update_columns(provider_order_id: "ORD01")
    { 401 => :connection, 409 => :conflict, 500 => :transient, 429 => :transient }.each do |code, family|
      error = assert_raises(TerminalProviders::Error) { run_with([ code, { "error" => "x" } ]) { |mp| mp.fetch_charge(@charge) } }
      assert_equal family, error.failure.family, code
    end
    error = assert_raises(TerminalProviders::Error) { run_with(error: Net::ReadTimeout.new) { |mp| mp.fetch_charge(@charge) } }
    assert error.failure.transient?
  end

  test "un monto rechazado al crear se reporta como fuera de rango" do
    error = assert_raises(TerminalProviders::Error) do
      run_with([ 400, { "errors" => [ { "code" => "invalid_amount" } ] } ]) { |mp| mp.create_charge(@charge) }
    end
    assert error.failure.declined?
    assert_equal "amount_out_of_range", error.failure.reason
  end

  test "lista dispositivos y prepara uno a PDV" do
    list = { "data" => { "terminals" => [ { "id" => "NEWLAND_N950__N950NCB801293324", "operating_mode" => "STANDALONE", "store_id" => "1", "pos_id" => 2 } ] },
             "paging" => { "total" => 1, "offset" => 0, "limit" => 50 } }
    (devices, total), = run_with([ 200, list ]) { |mp| mp.devices(@terminal.terminal_connection, limit: 50, offset: 0) }
    assert_equal 1, total
    assert_equal "STANDALONE", devices.first.mode
    assert_match(/…3324/, devices.first.label)

    setup_body = { "terminals" => [ { "id" => "NEWLAND_N950__N950NCB801293324", "operating_mode" => "PDV" } ] }
    result, http = run_with([ 200, list ], [ 200, setup_body ]) do |mp|
      mp.prepare_device(@terminal.terminal_connection, "NEWLAND_N950__N950NCB801293324")
    end
    assert result.restart_required
    assert_equal "/terminals/v1/setup", http.requests.last.path
    assert_equal "PDV", JSON.parse(http.requests.last.body).dig("terminals", 0, "operating_mode")
  end

  test "sin token legible es un error de conexión" do
    @terminal.terminal_connection.update_columns(access_token: nil)
    error = assert_raises(TerminalProviders::Error) { TerminalProviders::MercadoPago.new.fetch_charge(@charge.reload) }
    assert error.failure.connection?
  end

  test "la URL de autorización lleva PKCE, state y la URL de regreso fija" do
    with_env(MERCADO_PAGO_CLIENT_ID: "123", MERCADO_PAGO_CLIENT_SECRET: "s", FRONTEND_URL_UI: "https://app.example.test") do
      url = TerminalProviders::MercadoPago.new.authorize_url(state: "abc", code_challenge: "xyz")
      query = Rack::Utils.parse_query(URI(url).query)
      assert_equal "123", query["client_id"]
      assert_equal "abc", query["state"]
      assert_equal "S256", query["code_challenge_method"]
      assert_equal "https://app.example.test/terminales/mercado-pago", query["redirect_uri"]
    end
  end
end
