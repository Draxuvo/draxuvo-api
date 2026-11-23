require "test_helper"

# Spec 069 (contracts/api.md, Conexiones y Terminales): conectar Mercado Pago, dispositivos, ligar, preparar, desligar.
class Api::V1::TerminalConnectionsControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/terminal_connections".freeze

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @headers = auth_headers(@owner, @company)
  end

  def authorize_and_state(fake)
    post "#{BASE}/mercado_pago/authorize", headers: @headers, as: :json
    assert_response :ok
    Rack::Utils.parse_query(URI(response.parsed_body["url"]).query)["state"].tap { assert fake.calls_of(:authorize_url).any? }
  end

  test "el dueño conecta la cuenta con state y PKCE y nunca recibe tokens" do
    with_memory_cache do
      with_fake_provider do |fake|
        state = authorize_and_state(fake)
        post "#{BASE}/mercado_pago/callback", params: { code: "TG-1", state: state }, headers: @headers, as: :json
        assert_response :ok
        body = response.parsed_body
        assert_equal "connected", body["status"]
        assert_equal "Cuenta de prueba", body["account_label"]
        assert_not_includes response.body, "APP_USR"
        assert_not_includes response.body, "TG-refresh"
        assert fake.calls_of(:exchange_code).sole[:code_verifier].present?

        # El state es de un solo uso.
        post "#{BASE}/mercado_pago/callback", params: { code: "TG-1", state: state }, headers: @headers, as: :json
        assert_response :unprocessable_entity
        assert_equal "invalid_state", response.parsed_body.dig("error", "details", "code")
      end
    end
    connection = @company.terminal_connections.sole
    assert_equal "APP_USR-token", connection.token
    assert TerminalEvent.exists?(kind: "connected", company: @company)

    get BASE, headers: @headers
    provider = response.parsed_body["providers"].sole
    assert_equal "mercado_pago", provider["provider"]
    assert_equal connection.id, provider.dig("connection", "id")
  end

  test "un state de otro usuario o empresa no sirve" do
    with_memory_cache do
      with_fake_provider do |fake|
        state = authorize_and_state(fake)
        other = auth_headers(users(:enterprise_co_owner), companies(:enterprise_co))
        post "#{BASE}/mercado_pago/callback", params: { code: "TG-1", state: state }, headers: other, as: :json
        assert_response :unprocessable_entity
        assert_equal "invalid_state", response.parsed_body.dig("error", "details", "code")
      end
    end
  end

  test "si el proveedor rechaza el código responde authorization_failed" do
    with_memory_cache do
      with_fake_provider do |fake|
        fake.exchange_error = provider_error(:declined, "invalid_grant")
        state = authorize_and_state(fake)
        post "#{BASE}/mercado_pago/callback", params: { code: "TG-1", state: state }, headers: @headers, as: :json
        assert_response :unprocessable_entity
        assert_equal "authorization_failed", response.parsed_body.dig("error", "details", "code")
      end
    end
  end

  test "la misma cuenta puede conectarse en dos empresas" do
    with_memory_cache do
      with_fake_provider do |fake|
        state = authorize_and_state(fake)
        post "#{BASE}/mercado_pago/callback", params: { code: "TG-1", state: state }, headers: @headers, as: :json
        assert_response :ok

        other = auth_headers(users(:enterprise_co_owner), companies(:enterprise_co))
        post "#{BASE}/mercado_pago/authorize", headers: other, as: :json
        state2 = Rack::Utils.parse_query(URI(response.parsed_body["url"]).query)["state"]
        post "#{BASE}/mercado_pago/callback", params: { code: "TG-2", state: state2 }, headers: other, as: :json
        assert_response :ok
      end
    end
    assert_equal 2, TerminalConnection.where(account_id: "1001").count
  end

  test "sin credenciales de la plataforma no se ofrece OAuth (sí las credenciales propias)" do
    with_fake_provider do |fake|
      fake.available = false
      get BASE, headers: @headers
      provider = response.parsed_body["providers"].sole
      assert_equal false, provider["oauth"]
      assert provider["own_credentials"]
      post "#{BASE}/mercado_pago/authorize", headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "provider_unavailable", response.parsed_body.dig("error", "details", "code")
    end
  end

  test "el personal no ve ni cambia conexiones" do
    staff = auth_headers(users(:pro_staff), @company)
    get BASE, headers: staff
    assert_response :forbidden
    post "#{BASE}/mercado_pago/authorize", headers: staff, as: :json
    assert_response :forbidden
  end

  test "sin el módulo terminals responde module_not_in_plan" do
    get BASE, headers: auth_headers(users(:basic_co_owner), companies(:basic_co))
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  test "lista dispositivos paginados y marca los ligados" do
    connection = terminal_connection_for(@company)
    linked = integrated_terminal(@company, connection: connection)
    other_company_terminal = integrated_terminal(companies(:enterprise_co))
    with_fake_provider do |fake|
      fake.devices_list = [
        TerminalProviders::Device.new(id: "NEW__A", label: "A", mode: "STANDALONE"),
        TerminalProviders::Device.new(id: linked.device_id, label: "B", mode: "PDV"),
        TerminalProviders::Device.new(id: other_company_terminal.device_id, label: "C", mode: "PDV")
      ]
      get "#{BASE}/#{connection.id}/devices", params: { page: 1, page_size: 50 }, headers: @headers
      assert_response :ok
      body = response.parsed_body
      assert_equal 3, body.dig("info", "total")
      rows = body["results"].index_by { |row| row["device_id"] }
      assert rows["NEW__A"]["linkable"]
      assert_equal linked.id, rows[linked.device_id].dig("linked_terminal", "id")
      assert_equal "linked_elsewhere", rows[other_company_terminal.device_id]["reason"]
      assert_not rows[other_company_terminal.device_id]["linkable"]
    end
  end

  test "un token rechazado al listar deja la conexión con error" do
    connection = terminal_connection_for(@company)
    with_fake_provider do |fake|
      fake.devices_error = provider_error(:connection, "unauthorized", http_status: 401)
      Resend::Emails.stub(:send, ->(*) { resend_response }) do
        get "#{BASE}/#{connection.id}/devices", headers: @headers
      end
      assert_response :unprocessable_entity
      assert_equal "connection_error", response.parsed_body.dig("error", "details", "code")
    end
    assert connection.reload.error?
  end

  test "ligar dos terminales, una repetida da 409 y avisa reiniciar" do
    connection = terminal_connection_for(@company)
    with_fake_provider do
      post "/api/v1/payment_terminals", params: { payment_terminal: { name: "Caja 1", terminal_connection_id: connection.id, device_id: "NEW__1" } },
                                        headers: @headers, as: :json
      assert_response :created
      body = response.parsed_body
      assert_equal "integrated", body["kind"]
      assert_equal true, body["chargeable"]
      assert_equal true, body["restart_required"]
      assert_equal "mercado_pago", body["provider"]

      post "/api/v1/payment_terminals", params: { payment_terminal: { name: "Caja 2", terminal_connection_id: connection.id, device_id: "NEW__2" } },
                                        headers: @headers, as: :json
      assert_response :created

      post "/api/v1/payment_terminals", params: { payment_terminal: { name: "Caja 3", terminal_connection_id: connection.id, device_id: "NEW__1" } },
                                        headers: @headers, as: :json
      assert_response :conflict
      assert_equal "device_already_linked", response.parsed_body.dig("error", "details", "code")
    end
    assert_equal 2, @company.payment_terminals.where(terminal_connection: connection).count
  end

  test "un dispositivo que no admite el modo da device_not_supported" do
    connection = terminal_connection_for(@company)
    with_fake_provider do |fake|
      fake.prepare_error = provider_error(:device, "device_not_supported")
      post "/api/v1/payment_terminals", params: { payment_terminal: { name: "Caja 1", terminal_connection_id: connection.id, device_id: "NEW__1" } },
                                        headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "device_not_supported", response.parsed_body.dig("error", "details", "code")
    end
  end

  test "preparar y desligar" do
    terminal = integrated_terminal(@company)
    with_fake_provider do
      post "/api/v1/payment_terminals/#{terminal.id}/prepare", headers: @headers, as: :json
      assert_response :ok
      assert_equal "PDV", response.parsed_body["mode"]
    end
    post "/api/v1/payment_terminals/#{terminal.id}/unlink", headers: @headers, as: :json
    assert_response :ok
    assert_equal "manual", response.parsed_body["kind"]
    assert_nil terminal.reload.device_id
  end

  test "desconectar con una solicitud abierta da 422 y sin ella borra tokens" do
    terminal = integrated_terminal(@company)
    connection = terminal.terminal_connection
    charge = TerminalCharge.create!(company: @company, payment_terminal: terminal, terminal_connection: connection,
                                    created_by: @owner, amount: 10, work_order: work_orders(:pro_done))
    delete "#{BASE}/#{connection.id}", headers: @headers
    assert_response :unprocessable_entity
    assert_equal "terminal_charge_pending", response.parsed_body.dig("error", "details", "code")
    patch "/api/v1/payment_terminals/#{terminal.id}", params: { payment_terminal: { active: false } }, headers: @headers, as: :json
    assert_response :unprocessable_entity

    charge.update_columns(status: "canceled")
    delete "#{BASE}/#{connection.id}", headers: @headers
    assert_response :ok
    assert_equal "disconnected", response.parsed_body["status"]
    assert_nil connection.reload.token
    assert_not terminal.reload.chargeable?
  end

  test "en una demo no se puede conectar" do
    with_fake_provider do
      Current.stub(:demo, true) do
        TerminalConnections::Authorize.call(company: @company, user: @owner, provider: "mercado_pago")
      end
    rescue Demo::Restricted
      assert true
    else
      flunk "debió bloquearse en demo"
    end
  end
end
