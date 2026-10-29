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
    @code = WhatsappMessageType.find_by!(kind: "verification_code")
    @code.update_columns(template_status: "approved", enabled: true)
  end

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def listing(status: "APPROVED", name: "verification_code", language: "es_MX", text: "Tu código es {{1}}")
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
      patch_type("verification_code", { template_name: "mi_aviso", lock_version: @code.lock_version })
    end

    assert_response :ok
    code = type_json("verification_code")
    assert_equal "mi_aviso", code["template_name"]
    assert_equal "pending", code["template_status"]
    assert_equal false, code["enabled"]
    assert_nil code["stale"]
    assert_equal false, @code.reload.enabled
    assert WhatsappEvent.exists?(action: "template_changed", target: "verification_code")
    assert WhatsappEvent.exists?(action: "type_off", target: "verification_code")
    assert WhatsappEvent.exists?(action: "verified", target: "verification_code")
  end

  test "changing the language is also verified" do
    with_meta(listing(language: "en_US")) do
      patch_type("verification_code", { template_language: "en_US" })
    end

    assert_equal "en_US", @code.reload.template_language
    assert_equal "approved", @code.template_status
  end

  test "sending the same template changes nothing and does not call Meta" do
    http = with_meta { patch_type("verification_code", { template_name: @code.template_name, template_language: @code.template_language }) }

    assert_response :ok
    assert_empty http.requests
    assert @code.reload.enabled?
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
    with_meta(Net::ReadTimeout) { patch_type("verification_code", { template_name: "mi_aviso" }) }

    assert_response :ok
    code = type_json("verification_code")
    assert_equal "unknown", code["template_status"]
    assert_equal false, code["enabled"]
    assert_equal true, code["stale"]
  end

  test "an old lock version answers 409 stale_object" do
    with_meta(listing) do
      patch_type("verification_code", { template_name: "mi_aviso", lock_version: @code.lock_version + 4 })
    end

    assert_response :conflict
    assert_equal "stale_object", response.parsed_body.dig("error", "details", "code")
  end

  test "verify updates the state of the template" do
    with_meta(listing(status: "APPROVED")) { post "/api/v1/whatsapp/message_types/verification_code/verify", headers: @headers, as: :json }

    assert_response :ok
    code = type_json("verification_code")
    assert_equal "approved", code["template_status"]
    assert_not_nil code["template_checked_at"]
    assert_equal true, code["enabled"]
    assert WhatsappEvent.exists?(action: "verified", target: "verification_code", result: "ok")
  end

  test "verify on a Meta test account says templates cannot be checked there and keeps the type off" do
    @code.update_columns(enabled: false, template_status: "unknown")
    unsupported = http_response(Net::HTTPBadRequest, 400, "error" => { "code" => 100, "error_subcode" => 2_388_339, "message" => "Invalid parameter" })

    with_meta(unsupported) { post "/api/v1/whatsapp/message_types/verification_code/verify", headers: @headers, as: :json }

    assert_response :ok
    code = type_json("verification_code")
    assert_equal "unknown", code["template_status"]
    assert_equal I18n.t("whatsapp_admin.reasons.template_test_account"), code["template_detail"]
    assert_equal false, code["enabled"]
    assert_equal false, code["can_enable"]
  end

  test "verify on an enabled type whose template is no longer usable turns it off and warns the team once" do
    mails = []
    ResendMailer.stub(:whatsapp_alert, ->(**args) { mails << args }) do
      2.times do
        with_meta(listing(status: "PAUSED")) { post "/api/v1/whatsapp/message_types/verification_code/verify", headers: @headers, as: :json }
      end
    end

    assert_response :ok
    code = type_json("verification_code")
    assert_equal "rejected", code["template_status"]
    assert_equal false, code["enabled"]
    assert_equal "PAUSED", code["template_detail"]
    assert WhatsappEvent.exists?(action: "auto_off", target: "verification_code")
    assert_equal 1, mails.count { |mail| mail[:problem] == "template" }
  end

  test "verify with Meta down keeps the last known state and is marked stale" do
    with_meta(Net::OpenTimeout) { post "/api/v1/whatsapp/message_types/verification_code/verify", headers: @headers, as: :json }

    assert_response :ok
    code = type_json("verification_code")
    assert_equal "approved", code["template_status"]
    assert_equal true, code["stale"]
  end

  test "verify a ticket is rejected" do
    post "/api/v1/whatsapp/message_types/ticket/verify", headers: @headers, as: :json

    assert_response :unprocessable_entity
  end

  test "the guide lists the templates with name, language, category, body and variables, in Spanish and English" do
    get "/api/v1/whatsapp/guide", headers: @headers

    assert_response :ok
    results = response.parsed_body["results"]
    assert_equal %w[verification_code], results.map { |item| item["kind"] }, "solo queda la plantilla del código de verificación"
    code = results.first
    assert_equal "verification_code", code["name"]
    assert_equal "es_MX", code["language"]
    assert_equal "UTILITY", code["category"]
    assert_equal 1, code["variables"].size
    assert_equal({ "position" => 1 }, code["variables"].first.slice("position"))
    assert_equal 1, code["body"].scan(/\{\{\d\}\}/).size
    assert_not_includes response.body, "stock_bajo"
    spanish = code["body"]

    get "/api/v1/whatsapp/guide", headers: @headers.merge("Accept-Language" => "en")
    english = response.parsed_body["results"].find { |item| item["kind"] == "verification_code" }["body"]
    assert_not_equal spanish, english
  end

  test "the retired low stock type answers 404 to every action, like a type that does not exist (spec 048)" do
    ActiveRecord::Base.connection.execute(
      "INSERT INTO whatsapp_message_types (kind, enabled, template_name, template_language, template_status, lock_version, created_at, updated_at) " \
      "VALUES ('stock_alert', FALSE, 'stock_bajo', 'es_MX', 'approved', 0, NOW(), NOW())"
    )
    http = with_meta do
      patch_type("stock_alert", { enabled: true })
      assert_response :not_found
      patch_type("stock_alert", { template_name: "otra" })
      assert_response :not_found
      post "/api/v1/whatsapp/message_types/stock_alert/verify", headers: @headers, as: :json
      assert_response :not_found
      post_test("stock_alert", { phone: "5512345678" })
      assert_response :not_found
    end

    assert_empty http.requests
    assert_equal false, WhatsappMessageType.find_by!(kind: "stock_alert").enabled
    assert_not WhatsappEvent.exists?(target: "stock_alert")
  end

  test "turning a type on needs an approved template and logs type_on; turning it off is never blocked" do
    @code.update_columns(enabled: false)

    patch_type("verification_code", { enabled: true })
    assert_response :ok
    assert_equal true, type_json("verification_code")["enabled"]
    assert WhatsappEvent.exists?(action: "type_on", target: "verification_code")

    patch_type("verification_code", { enabled: false })
    assert_response :ok
    assert_equal false, type_json("verification_code")["enabled"]
    assert WhatsappEvent.exists?(action: "type_off", target: "verification_code")
  end

  test "turning a type on without an approved template answers 422 template_not_approved" do
    @code.update_columns(enabled: false, template_status: "pending")

    patch_type("verification_code", { enabled: true })

    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "template_not_approved", details["code"]
    assert_equal "pending", details["template_status"]
    assert_equal false, @code.reload.enabled
  end

  test "turning a type on with an incompatible template answers 422 template_incompatible" do
    @code.update_columns(enabled: false, template_status: "incompatible")

    patch_type("verification_code", { enabled: true })

    assert_response :unprocessable_entity
    assert_equal "template_incompatible", response.parsed_body.dig("error", "details", "code")
  end

  test "turning a type on without a connection answers 422 not_connected" do
    @code.update_columns(enabled: false)
    WhatsappConnection.first.update_columns(status: "not_connected")

    patch_type("verification_code", { enabled: true })

    assert_response :unprocessable_entity
    assert_equal "not_connected", response.parsed_body.dig("error", "details", "code")
  end

  test "tickets only need the connection to be turned on" do
    patch_type("ticket", { enabled: true })

    assert_response :ok
    assert_equal true, type_json("ticket")["enabled"]
    assert_equal true, type_json("ticket")["can_enable"]
  end

  test "turning one type off leaves the others as they were" do
    WhatsappMessageType.find_by!(kind: "ticket").update_columns(enabled: true)

    patch_type("verification_code", { enabled: false })

    assert_equal false, type_json("verification_code")["enabled"]
    assert_equal true, type_json("ticket")["enabled"]
  end

  def delivered = http_response(Net::HTTPOK, 200, "messages" => [ { "id" => "wamid.1" } ])

  def post_test(kind, params = {}, headers: @headers)
    post "/api/v1/whatsapp/message_types/#{kind}/test", params: params, headers: headers, as: :json
  end

  def log_tests(count, user: @super_admin)
    count.times { WhatsappEvent.log!(action: "test_sent", target: "ticket", user: user, data: { to: "••••0000" }) }
  end

  test "a test message is sent after re-checking the template, masks the number and counts toward the limit" do
    with_meta(listing, delivered) { post_test("verification_code", { phone: "55 1234 5678" }) }

    assert_response :ok
    body = response.parsed_body
    assert_equal "sent", body["result"]
    assert_equal "••••5678", body["to"]
    assert_equal 4, body["tests_remaining"]
    event = WhatsappEvent.find_by!(action: "test_sent", target: "verification_code")
    assert_equal "ok", event.result
    assert_equal({ "to" => "••••5678" }, event.data)
    assert_not_includes event.to_json, "5512345678"
    assert_not_includes response.body, "5512345678"
  end

  test "it works with the channel off" do
    assert_not WhatsappConnection.first.enabled?

    with_meta(delivered) { post_test("ticket", { phone: "5512345678" }) }

    assert_response :ok
  end

  test "it uses the profile phone when none is given" do
    @super_admin.update_columns(phone: "5598765432")

    with_meta(delivered) { post_test("ticket") }

    assert_response :ok
    assert_equal "••••5432", response.parsed_body["to"]
  end

  test "a phone that is not 10 to 15 digits answers 422 invalid_phone and calls nothing" do
    http = with_meta { post_test("ticket", { phone: "12345" }) }

    assert_response :unprocessable_entity
    assert_equal "invalid_phone", response.parsed_body.dig("error", "details", "code")
    assert_empty http.requests
  end

  test "the sixth test in an hour answers 429, per user" do
    log_tests(5)

    with_meta(delivered) { post_test("ticket", { phone: "5512345678" }) }

    assert_response :too_many_requests
    assert_equal "tests_limit", response.parsed_body.dig("error", "details", "code")

    other = User.create!(first_name: "Otro", last_name: "Admin", email: "otro-admin@draxuvo.test", phone: "5511112222",
                         password: "password123", active: true, role: :super_admin)
    with_meta(delivered) { post_test("ticket", { phone: "5512345678" }, headers: auth_headers(other, nil)) }
    assert_response :ok
  end

  test "tests older than an hour no longer count" do
    log_tests(5)
    WhatsappEvent.where(action: "test_sent").update_all(created_at: 2.hours.ago)

    with_meta(delivered) { post_test("ticket", { phone: "5512345678" }) }

    assert_response :ok
  end

  test "a template that is no longer approved blocks the test with 422" do
    @code.update_columns(enabled: false)
    with_meta(listing(status: "PAUSED")) { post_test("verification_code", { phone: "5512345678" }) }

    assert_response :unprocessable_entity
    assert_equal "template_not_approved", response.parsed_body.dig("error", "details", "code")
    assert_not WhatsappEvent.exists?(action: "test_sent")
  end

  test "without a connection the test answers 422 not_connected" do
    WhatsappConnection.first.update_columns(status: "not_connected")

    post_test("ticket", { phone: "5512345678" })

    assert_response :unprocessable_entity
    assert_equal "not_connected", response.parsed_body.dig("error", "details", "code")
  end

  test "a recipient Meta rejects answers 422 with the reason, logs the failure and counts it" do
    with_meta(http_response(Net::HTTPBadRequest, 400, "error" => { "code" => 131_030, "message" => "x" })) do
      post_test("ticket", { phone: "5512345678" })
    end

    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "test_failed", details["code"]
    assert_equal "not_authorized_recipient", details["reason"]
    assert_equal "131030", details["meta_code"]
    assert WhatsappEvent.exists?(action: "test_sent", result: "failed")
  end

  test "with Meta down the test answers 503 and does not count" do
    with_meta(Net::ReadTimeout) { post_test("ticket", { phone: "5512345678" }) }

    assert_response :service_unavailable
    assert_equal "meta_unreachable", response.parsed_body.dig("error", "details", "code")
    assert_not WhatsappEvent.exists?(action: "test_sent")
  end

  test "a test is not a real send: it changes no switch" do
    @code.update_columns(enabled: false)

    with_meta(listing, delivered) { post_test("verification_code", { phone: "5512345678" }) }

    assert_equal false, @code.reload.enabled
  end

  test "owner, admin and staff cannot send tests" do
    company = companies(:enterprise_co)
    %w[owner admin staff].each do |role|
      post_test("ticket", { phone: "5512345678" }, headers: auth_headers(create_member(company, role: role), company))

      assert_response :forbidden, "test as #{role}"
    end
  end

  test "owner, admin and staff are forbidden" do
    company = companies(:enterprise_co)
    %w[owner admin staff].each do |role|
      headers = auth_headers(create_member(company, role: role), company)

      patch_type("verification_code", { template_name: "x" }, headers: headers)
      assert_response :forbidden, "PATCH as #{role}"
      post "/api/v1/whatsapp/message_types/verification_code/verify", headers: headers, as: :json
      assert_response :forbidden, "verify as #{role}"
      get "/api/v1/whatsapp/guide", headers: headers
      assert_response :forbidden, "guide as #{role}"
    end
  end
end
