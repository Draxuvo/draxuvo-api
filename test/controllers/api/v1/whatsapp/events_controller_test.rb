require "test_helper"

# Spec 047, US5: historial de la configuración de WhatsApp, sin secretos.
class WhatsappEventsControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "EAAGtokensecretoZQ7K".freeze
  NEW_TOKEN = "EAAGlavenuevasecretaXW3P".freeze
  PHONE = "104512345678901".freeze
  WABA = "109876543210987".freeze

  FakeHttp = Struct.new(:responses, :requests) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      responses.length > 1 ? responses.shift : responses.first
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

  def with_meta(*responses)
    http = FakeHttp.new(responses, [])
    Net::HTTP.stub(:new, ->(*) { http }) { yield }
  end

  def events = response.parsed_body["results"]

  test "it lists events paginated, the most recent first" do
    WhatsappEvent.log!(action: "channel_on", target: "connection", user: @super_admin)
    WhatsappEvent.log!(action: "type_on", target: "stock_alert", user: @super_admin, data: { from: false, to: true })

    get "/api/v1/whatsapp/events", headers: @headers

    assert_response :ok
    body = response.parsed_body
    assert_equal %w[info results], body.keys.sort
    assert_equal %w[type_on channel_on], events.map { |event| event["action"] }
    assert_equal 2, body.dig("info", "total")
    first = events.first
    assert_equal({ "id" => @super_admin.id, "name" => @super_admin.full_name }, first["user"])
    assert_equal({ "from" => false, "to" => true }, first["data"])
    assert_equal "stock_alert", first["target"]
    assert_equal "ok", first["result"]
    assert_not_nil first["created_at"]
  end

  test "it paginates" do
    3.times { WhatsappEvent.log!(action: "channel_on", target: "connection", user: @super_admin) }

    get "/api/v1/whatsapp/events", params: { page_size: 2 }, headers: @headers

    assert_equal 2, events.size
    assert_equal 3, response.parsed_body.dig("info", "total")
  end

  test "automatic turn-offs and alerts have no user" do
    WhatsappEvent.log!(action: "auto_off", target: "stock_alert", result: "failed", meta_code: 132_001, data: { reason: "template_missing" })

    get "/api/v1/whatsapp/events", headers: @headers

    assert_nil events.first["user"]
    assert_equal "132001", events.first["meta_code"]
  end

  test "phone numbers in the history are masked" do
    WhatsappEvent.log!(action: "test_sent", target: "ticket", user: @super_admin, data: { to: WhatsappEvent.mask_phone("5512345678") })

    get "/api/v1/whatsapp/events", headers: @headers

    assert_equal "••••5678", events.first.dig("data", "to")
    assert_not_includes response.body, "5512345678"
  end

  test "connecting and replacing the key leave events that never contain the key, not even a part of it" do
    with_meta(phone_ok, numbers_ok) do
      put "/api/v1/whatsapp/connection", params: { access_token: TOKEN, phone_number_id: PHONE, waba_id: WABA }, headers: @headers, as: :json
      put "/api/v1/whatsapp/connection", params: { access_token: NEW_TOKEN }, headers: @headers, as: :json
    end

    get "/api/v1/whatsapp/events", headers: @headers

    assert_equal %w[token_replaced connected], events.map { |event| event["action"] }
    [ TOKEN, NEW_TOKEN, "ZQ7K", "XW3P", "EAAG" ].each { |piece| assert_not_includes response.body, piece }
    assert_not_includes WhatsappEvent.all.map(&:attributes).to_json, "ZQ7K"
  end

  test "owner, admin, staff and anonymous requests are rejected" do
    company = companies(:enterprise_co)
    %w[owner admin staff].each do |role|
      get "/api/v1/whatsapp/events", headers: auth_headers(create_member(company, role: role), company)

      assert_response :forbidden, "events as #{role}"
    end

    get "/api/v1/whatsapp/events"
    assert_response :unauthorized
  end
end
