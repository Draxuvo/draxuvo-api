require "test_helper"

# Spec 047, US1: conectar, verificar, reemplazar la llave y desconectar. Meta se simula; nunca hay llamadas reales.
class WhatsappConnectionsControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "EAAGtokensecreto1234567890".freeze
  NEW_TOKEN = "EAAGotrallavenueva00009999".freeze
  PHONE = "104512345678901".freeze
  WABA = "109876543210987".freeze
  PATH = "/api/v1/whatsapp/connection".freeze

  FakeHttp = Struct.new(:responses, :requests) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      response = responses.shift
      raise response if response.is_a?(Class) && response <= Exception

      response
    end
  end

  setup do
    @super_admin = users(:super_admin)
    @headers = auth_headers(@super_admin, nil)
  end

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def phone_ok = http_response(Net::HTTPOK, 200, "verified_name" => "Draxuvo", "display_phone_number" => "+52 55 1234 5678")

  def numbers_ok = http_response(Net::HTTPOK, 200, "data" => [ { "id" => PHONE } ])

  def meta_error(code, subcode: nil)
    error = { "code" => code, "message" => "msg" }
    error["error_subcode"] = subcode if subcode
    http_response(Net::HTTPBadRequest, 400, "error" => error)
  end

  # Corre la petición con Meta simulado y devuelve el http falso.
  def with_meta(*responses)
    http = FakeHttp.new(responses, [])
    Net::HTTP.stub(:new, ->(*) { http }) { yield }
    http
  end

  def connect!(token: TOKEN)
    WhatsappConnection.current.update!(access_token: token, phone_number_id: PHONE, waba_id: WABA, status: "connected",
                                       managed: true, verified_name: "Draxuvo")
  end

  def body_params(extra = {})
    { access_token: TOKEN, phone_number_id: PHONE, waba_id: WABA }.merge(extra)
  end

  test "PUT connects a Meta test account and warns that templates cannot be checked" do
    with_meta(phone_ok, meta_error(100, subcode: 2_388_339)) { put PATH, params: body_params, headers: @headers, as: :json }

    assert_response :ok
    assert_equal "connected", WhatsappConnection.first.status
    assert_equal "test_account", response.parsed_body["notice"]
    assert_equal true, WhatsappEvent.find_by!(action: "connected").data["test_account"]
    assert_not_includes response.body, TOKEN
  end

  test "a regular connection carries no notice" do
    with_meta(phone_ok, numbers_ok) { put PATH, params: body_params, headers: @headers, as: :json }

    assert_nil response.parsed_body["notice"]
    assert_nil WhatsappEvent.find_by!(action: "connected").data["test_account"]
  end

  test "PUT saves a verified connection as connected and managed, and never returns the key" do
    with_meta(phone_ok, numbers_ok) { put PATH, params: body_params, headers: @headers, as: :json }

    assert_response :ok
    connection = WhatsappConnection.first
    assert_equal "connected", connection.status
    assert connection.managed?
    assert_equal TOKEN, connection.token
    assert_equal "Draxuvo", connection.verified_name
    assert_equal "panel", response.parsed_body["source"]
    assert_equal "connected", response.parsed_body.dig("connection", "status")
    assert_equal TOKEN.last(4), response.parsed_body.dig("connection", "token_hint")
    assert_not_includes response.body, TOKEN
    event = WhatsappEvent.find_by!(action: "connected")
    assert_equal @super_admin.id, event.user_id
    assert_not_includes event.data.to_json, TOKEN
  end

  test "a rejection changes nothing that was saved" do
    connect!
    before = WhatsappConnection.first.attributes.slice("phone_number_id", "waba_id", "status", "verified_name")

    with_meta(meta_error(190)) do
      put PATH, params: body_params(access_token: NEW_TOKEN, phone_number_id: "999999999"), headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "whatsapp_rejected", details["code"]
    assert_equal "invalid_token", details["reason"]
    assert_equal "190", details["meta_code"]
    connection = WhatsappConnection.first
    assert_equal before, connection.attributes.slice("phone_number_id", "waba_id", "status", "verified_name")
    assert_equal TOKEN, connection.token
    assert_not_includes response.body, NEW_TOKEN
  end

  test "the key is required the first time and optional afterwards" do
    put PATH, params: body_params.except(:access_token), headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "token_required", response.parsed_body.dig("error", "details", "code")

    connect!
    with_meta(phone_ok, numbers_ok) { put PATH, params: body_params.except(:access_token), headers: @headers, as: :json }
    assert_response :ok
  end

  test "replacing only the key keeps the number and the chosen templates" do
    connect!
    WhatsappMessageType.ensure_all!
    WhatsappMessageType.find_by!(kind: "verification_code").update!(template_name: "mi_plantilla")

    with_meta(phone_ok, numbers_ok) do
      put PATH, params: { access_token: NEW_TOKEN, lock_version: WhatsappConnection.first.lock_version }, headers: @headers, as: :json
    end

    assert_response :ok
    connection = WhatsappConnection.first
    assert_equal NEW_TOKEN, connection.token
    assert_equal PHONE, connection.phone_number_id
    assert_equal "mi_plantilla", WhatsappMessageType.find_by!(kind: "verification_code").template_name
    assert WhatsappEvent.exists?(action: "token_replaced")
  end

  test "PUT answers 409 stale_object with the current state when the lock version is old" do
    connect!

    with_meta(phone_ok, numbers_ok) do
      put PATH, params: body_params(lock_version: WhatsappConnection.first.lock_version + 5), headers: @headers, as: :json
    end

    assert_response :conflict
    details = response.parsed_body.dig("error", "details")
    assert_equal "stale_object", details["code"]
    assert_equal "connected", details.dig("current", "connection", "status")
    assert_not_includes response.body, TOKEN
  end

  test "PUT answers 503 meta_unreachable when Meta does not answer and saves nothing" do
    with_meta(Net::ReadTimeout) { put PATH, params: body_params, headers: @headers, as: :json }

    assert_response :service_unavailable
    assert_equal "meta_unreachable", response.parsed_body.dig("error", "details", "code")
    assert_nil WhatsappConnection.first&.token
  end

  test "verify turns the connection to connected or error" do
    connect!
    WhatsappConnection.first.update!(status: "error", error_code: "190", error_message: "x")

    with_meta(phone_ok, numbers_ok) { post "#{PATH}/verify", headers: @headers, as: :json }
    assert_response :ok
    assert_equal "connected", response.parsed_body.dig("connection", "status")
    assert WhatsappEvent.exists?(action: "verified", result: "ok")

    mails = []
    ResendMailer.stub(:whatsapp_alert, ->(**args) { mails << args }) do
      with_meta(meta_error(190, subcode: 463)) { post "#{PATH}/verify", headers: @headers, as: :json }
    end
    assert_response :ok
    assert_equal 1, mails.map { |m| m[:problem] }.count("connection")
    assert_equal "error", response.parsed_body.dig("connection", "status")
    assert WhatsappEvent.exists?(action: "verified", result: "failed")
  end

  test "verify with Meta down keeps the previous state and marks it stale" do
    connect!

    with_meta(Net::OpenTimeout) { post "#{PATH}/verify", headers: @headers, as: :json }

    assert_response :ok
    assert_equal true, response.parsed_body.dig("connection", "stale")
    assert_equal "connected", WhatsappConnection.first.status
  end

  test "verify without a saved connection answers 422" do
    post "#{PATH}/verify", headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "not_connected", response.parsed_body.dig("error", "details", "code")
  end

  test "DELETE with the channel on needs confirmation, then clears the key and turns everything off but keeps templates" do
    connect!
    WhatsappMessageType.ensure_all!
    WhatsappMessageType.find_by!(kind: "ticket").update!(enabled: true)
    WhatsappConnection.first.update!(enabled: true)

    delete PATH, params: {}, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "confirmation_required", response.parsed_body.dig("error", "details", "code")
    assert WhatsappConnection.first.enabled?

    code = WhatsappMessageType.find_by!(kind: "verification_code")
    code.update!(template_name: "mi_plantilla")
    delete PATH, params: { confirm: true }, headers: @headers, as: :json

    assert_response :ok
    connection = WhatsappConnection.first
    assert_nil connection.token
    assert_equal "not_connected", connection.status
    assert_not connection.enabled?
    assert_not WhatsappMessageType.where(enabled: true).exists?
    assert_equal "mi_plantilla", code.reload.template_name
    assert WhatsappEvent.exists?(action: "disconnected")
  end

  test "DELETE with the channel off needs no confirmation" do
    connect!

    delete PATH, params: {}, headers: @headers, as: :json

    assert_response :ok
  end

  test "owner, admin and staff are forbidden" do
    company = companies(:enterprise_co)
    %w[owner admin staff].each do |role|
      member = create_member(company, role: role)
      headers = auth_headers(member, company)

      put PATH, params: body_params, headers: headers, as: :json
      assert_response :forbidden, "PUT as #{role}"
      post "#{PATH}/verify", headers: headers, as: :json
      assert_response :forbidden, "verify as #{role}"
      delete PATH, headers: headers, as: :json
      assert_response :forbidden, "DELETE as #{role}"
    end
  end
end
