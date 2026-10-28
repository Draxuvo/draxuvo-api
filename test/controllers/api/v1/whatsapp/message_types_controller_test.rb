require "test_helper"

# Spec 047, US2: elegir y verificar la plantilla de cada tipo, y la guía para crearlas en Meta. Meta se simula.
class WhatsappMessageTypesControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "EAAGtokensecreto1234567890".freeze
  PHONE = "104512345678901".freeze
  WABA = "109876543210987".freeze

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
    WhatsappConnection.current.update!(access_token: TOKEN, phone_number_id: PHONE, waba_id: WABA, status: "connected", managed: true)
    WhatsappMessageType.ensure_all!
    @stock = WhatsappMessageType.find_by!(kind: "stock_alert")
    @stock.update_columns(template_status: "approved", enabled: true)
  end

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def listing(status: "APPROVED", name: "stock_bajo", language: "es_MX", text: "Stock bajo en {{1}}: {{2}} ({{3}})")
    row = { "name" => name, "language" => language, "status" => status, "components" => [ { "type" => "BODY", "text" => text } ] }
    http_response(Net::HTTPOK, 200, "data" => [ row ])
  end

  def with_meta(*responses)
    http = FakeHttp.new(responses, [])
    Net::HTTP.stub(:new, ->(*) { http }) { yield }
    http
  end

  def type_json(kind) = response.parsed_body["message_types"].find { |type| type["kind"] == kind }

  def patch_type(kind, params, headers: @headers)
    patch "/api/v1/whatsapp/message_types/#{kind}", params: params, headers: headers, as: :json
  end

  test "changing the template verifies it right away, turns the type off and saves the new state" do
    with_meta(listing(name: "mi_aviso", status: "PENDING")) do
      patch_type("stock_alert", { template_name: "mi_aviso", lock_version: @stock.lock_version })
    end

    assert_response :ok
    stock = type_json("stock_alert")
    assert_equal "mi_aviso", stock["template_name"]
    assert_equal "pending", stock["template_status"]
    assert_equal false, stock["enabled"]
    assert_nil stock["stale"]
    assert_equal false, @stock.reload.enabled
    assert WhatsappEvent.exists?(action: "template_changed", target: "stock_alert")
    assert WhatsappEvent.exists?(action: "type_off", target: "stock_alert")
    assert WhatsappEvent.exists?(action: "verified", target: "stock_alert")
  end

  test "changing the language is also verified" do
    with_meta(listing(language: "en_US")) do
      patch_type("stock_alert", { template_language: "en_US" })
    end

    assert_equal "en_US", @stock.reload.template_language
    assert_equal "approved", @stock.template_status
  end

  test "sending the same template changes nothing and does not call Meta" do
    http = with_meta { patch_type("stock_alert", { template_name: @stock.template_name, template_language: @stock.template_language }) }

    assert_response :ok
    assert_empty http.requests
    assert @stock.reload.enabled?
  end

  test "tickets reject a template with 422" do
    patch_type("ticket", { template_name: "algo" })

    assert_response :unprocessable_entity
    assert_equal "ticket_has_no_template", response.parsed_body.dig("error", "details", "code")
  end

  test "an unknown kind is not found" do
    patch_type("otra_cosa", { template_name: "x" })

    assert_response :not_found
  end

  test "with Meta down the type stays off with an unknown status and is marked stale" do
    with_meta(Net::ReadTimeout) { patch_type("stock_alert", { template_name: "mi_aviso" }) }

    assert_response :ok
    stock = type_json("stock_alert")
    assert_equal "unknown", stock["template_status"]
    assert_equal false, stock["enabled"]
    assert_equal true, stock["stale"]
  end

  test "an old lock version answers 409 stale_object" do
    with_meta(listing) do
      patch_type("stock_alert", { template_name: "mi_aviso", lock_version: @stock.lock_version + 4 })
    end

    assert_response :conflict
    assert_equal "stale_object", response.parsed_body.dig("error", "details", "code")
  end

  test "verify updates the state of the template" do
    with_meta(listing(status: "APPROVED")) { post "/api/v1/whatsapp/message_types/stock_alert/verify", headers: @headers, as: :json }

    assert_response :ok
    stock = type_json("stock_alert")
    assert_equal "approved", stock["template_status"]
    assert_not_nil stock["template_checked_at"]
    assert_equal true, stock["enabled"]
    assert WhatsappEvent.exists?(action: "verified", target: "stock_alert", result: "ok")
  end

  test "verify on an enabled type whose template is no longer usable turns it off and warns the team once" do
    mails = []
    ResendMailer.stub(:whatsapp_alert, ->(**args) { mails << args }) do
      2.times do
        with_meta(listing(status: "PAUSED")) { post "/api/v1/whatsapp/message_types/stock_alert/verify", headers: @headers, as: :json }
      end
    end

    assert_response :ok
    stock = type_json("stock_alert")
    assert_equal "rejected", stock["template_status"]
    assert_equal false, stock["enabled"]
    assert_equal "PAUSED", stock["template_detail"]
    assert WhatsappEvent.exists?(action: "auto_off", target: "stock_alert")
    assert_equal 1, mails.count { |mail| mail[:problem] == "template" }
  end

  test "verify with Meta down keeps the last known state and is marked stale" do
    with_meta(Net::OpenTimeout) { post "/api/v1/whatsapp/message_types/stock_alert/verify", headers: @headers, as: :json }

    assert_response :ok
    stock = type_json("stock_alert")
    assert_equal "approved", stock["template_status"]
    assert_equal true, stock["stale"]
  end

  test "verify a ticket is rejected" do
    post "/api/v1/whatsapp/message_types/ticket/verify", headers: @headers, as: :json

    assert_response :unprocessable_entity
  end

  test "the guide lists the templates with name, language, category, body and variables, in Spanish and English" do
    get "/api/v1/whatsapp/guide", headers: @headers

    assert_response :ok
    results = response.parsed_body["results"]
    assert_equal %w[verification_code stock_alert].sort, results.map { |item| item["kind"] }.sort
    stock = results.find { |item| item["kind"] == "stock_alert" }
    assert_equal "stock_bajo", stock["name"]
    assert_equal "es_MX", stock["language"]
    assert_equal "UTILITY", stock["category"]
    assert_equal 3, stock["variables"].size
    assert_equal({ "position" => 1 }, stock["variables"].first.slice("position"))
    assert_equal 3, stock["body"].scan(/\{\{\d\}\}/).size
    spanish = stock["body"]

    get "/api/v1/whatsapp/guide", headers: @headers.merge("Accept-Language" => "en")
    english = response.parsed_body["results"].find { |item| item["kind"] == "stock_alert" }["body"]
    assert_not_equal spanish, english
  end

  test "owner, admin and staff are forbidden" do
    company = companies(:enterprise_co)
    %w[owner admin staff].each do |role|
      headers = auth_headers(create_member(company, role: role), company)

      patch_type("stock_alert", { template_name: "x" }, headers: headers)
      assert_response :forbidden, "PATCH as #{role}"
      post "/api/v1/whatsapp/message_types/stock_alert/verify", headers: headers, as: :json
      assert_response :forbidden, "verify as #{role}"
      get "/api/v1/whatsapp/guide", headers: headers
      assert_response :forbidden, "guide as #{role}"
    end
  end
end
