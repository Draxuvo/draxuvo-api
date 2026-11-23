require "test_helper"

# Spec 069, credenciales propias: el dueño o administrador conecta Mercado Pago pegando el Access Token de su aplicación,
# sin OAuth, y recibe los avisos en la URL de su conexión, firmados con su propia clave secreta.
class Api::V1::TerminalConnectionsOwnCredentialsTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/terminal_connections".freeze
  TOKEN = "APP_USR-1234567890123456-112233-abcdef0123456789abcdef0123456789-987654321".freeze

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @headers = auth_headers(@owner, @company)
  end

  def put_credentials(headers: @headers, **params)
    put "#{BASE}/mercado_pago/credentials", params: params, headers: headers, as: :json
  end

  test "el dueño conecta con su Access Token y nunca recibe el token ni la clave" do
    with_fake_provider do |fake|
      fake.available = false # sin aplicación de Draxuvo: igual se puede conectar
      put_credentials(access_token: "  #{TOKEN} ", webhook_secret: "clave-del-aviso")
      assert_response :ok
      assert_equal TOKEN, fake.calls_of(:verify_token).sole[:access_token]
    end
    body = response.parsed_body
    assert_equal "connected", body["status"]
    assert_equal "token", body["auth_method"]
    assert_equal "Cuenta propia", body["account_label"]
    assert_equal "…4321", body["token_hint"]
    assert body["webhook_secret_present"]
    assert_match %r{/api/v1/webhooks/mercado_pago/[\w-]{20,}\z}, body["webhook_url"]
    assert_not_includes response.body, "abcdef0123456789"
    assert_not_includes response.body, "clave-del-aviso"

    connection = @company.terminal_connections.sole
    assert_equal TOKEN, connection.token
    assert_nil connection.renewal_token
    assert_equal "clave-del-aviso", connection.signing_secret
    assert TerminalEvent.exists?(kind: "connected", terminal_connection: connection)

    get BASE, headers: @headers
    provider = response.parsed_body["providers"].sole
    assert provider["available"]
    assert provider["own_credentials"]
  end

  test "sin la aplicación de Draxuvo la lista ofrece solo credenciales propias" do
    with_fake_provider do |fake|
      fake.available = false
      get BASE, headers: @headers
    end
    provider = response.parsed_body["providers"].sole
    assert provider["available"]
    assert_not provider["oauth"]
    assert provider["own_credentials"]
  end

  test "un token con formato raro no se manda al proveedor" do
    with_fake_provider do |fake|
      put_credentials(access_token: "hola")
      assert_response :unprocessable_entity
      assert_equal "access_token_invalid", response.parsed_body.dig("error", "details", "code")
      assert_empty fake.calls_of(:verify_token)
    end
    assert_empty @company.terminal_connections
  end

  test "el rechazo del proveedor se explica" do
    with_fake_provider do |fake|
      fake.verify_error = provider_error(:connection, "unauthorized", http_status: 401)
      put_credentials(access_token: TOKEN)
      assert_equal "access_token_rejected", response.parsed_body.dig("error", "details", "code")

      fake.verify_error = provider_error(:connection, "point_not_enabled", http_status: 403)
      put_credentials(access_token: TOKEN)
      assert_equal "point_not_enabled", response.parsed_body.dig("error", "details", "code")

      fake.verify_error = provider_error(:transient, "provider_unavailable")
      put_credentials(access_token: TOKEN)
      assert_equal "provider_down", response.parsed_body.dig("error", "details", "code")
    end
    assert_empty @company.terminal_connections
  end

  test "cambiar solo la clave secreta deja el token como estaba" do
    with_fake_provider do |fake|
      put_credentials(access_token: "")
      assert_equal "access_token_missing", response.parsed_body.dig("error", "details", "code")

      put_credentials(access_token: TOKEN)
      assert_response :ok
      assert_not response.parsed_body["webhook_secret_present"]
      url = response.parsed_body["webhook_url"]

      put_credentials(access_token: "", webhook_secret: "nueva")
      assert_response :ok
      assert response.parsed_body["webhook_secret_present"]
      assert_equal url, response.parsed_body["webhook_url"]
      assert_equal 1, fake.calls_of(:verify_token).size
    end
    connection = @company.terminal_connections.sole
    assert_equal TOKEN, connection.token
    assert_equal "nueva", connection.signing_secret
    assert TerminalEvent.exists?(kind: "webhook_secret_changed", terminal_connection: connection)
  end

  test "desconectar borra token y clave pero conserva la URL de avisos" do
    with_fake_provider { put_credentials(access_token: TOKEN, webhook_secret: "s") }
    connection = @company.terminal_connections.sole
    url_token = connection.webhook_token
    delete "#{BASE}/#{connection.id}", headers: @headers
    assert_response :ok
    connection.reload
    assert_nil connection.token
    assert_nil connection.signing_secret
    assert_equal url_token, connection.webhook_token
    assert_nil response.parsed_body["token_hint"]
  end

  test "el personal no puede conectar" do
    staff = auth_headers(users(:pro_staff), @company)
    with_fake_provider { put_credentials(headers: staff, access_token: TOKEN) }
    assert_response :forbidden
  end

  test "la renovación diaria no toca las conexiones con credenciales propias" do
    with_fake_provider { put_credentials(access_token: TOKEN) }
    with_fake_provider do |fake|
      TerminalConnections::RefreshJob.perform_now
      assert_empty fake.calls_of(:refresh)
    end
    assert @company.terminal_connections.sole.connected?
  end

  test "el aviso de una conexión propia se valida con su clave y solo busca sus cobros" do
    with_fake_provider { put_credentials(access_token: TOKEN, webhook_secret: "propia") }
    connection = @company.terminal_connections.sole
    terminal = integrated_terminal(@company, connection: connection)
    charge = TerminalCharge.create!(company: @company, payment_terminal: terminal, terminal_connection: connection,
                                    created_by: @owner, amount: 10, work_order: work_orders(:pro_open), provider_order_id: "ORDPROPIA")
    url = "/api/v1/webhooks/mercado_pago/#{connection.webhook_token}?data.id=ORDPROPIA&type=order"

    with_env(MERCADO_PAGO_WEBHOOK_SECRET: "de-draxuvo") do
      post url, params: { type: "order" }.to_json,
                headers: mp_webhook_headers(data_id: "ORDPROPIA", secret: "de-draxuvo").merge("CONTENT_TYPE" => "application/json")
      assert_response :bad_request

      assert_enqueued_with(job: TerminalCharges::SyncJob, args: [ charge.id ]) do
        post url, params: { type: "order" }.to_json,
                  headers: mp_webhook_headers(data_id: "ORDPROPIA", secret: "propia").merge("CONTENT_TYPE" => "application/json")
      end
      assert_response :ok
    end

    post "/api/v1/webhooks/mercado_pago/no-existe?data.id=ORDPROPIA", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
  end

  test "sin clave guardada el aviso de una conexión propia se rechaza" do
    with_fake_provider { put_credentials(access_token: TOKEN) }
    connection = @company.terminal_connections.sole
    post "/api/v1/webhooks/mercado_pago/#{connection.webhook_token}?data.id=ORD1&type=order", params: {}.to_json,
         headers: mp_webhook_headers(data_id: "ORD1", secret: "x").merge("CONTENT_TYPE" => "application/json")
    assert_response :bad_request
  end
end
