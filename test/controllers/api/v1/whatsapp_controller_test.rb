require "test_helper"

# Spec 047: el estado de WhatsApp es solo del super admin, sin empresa, y nunca incluye la llave.
class WhatsappControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "EAAGsecretokenvalue9f3a".freeze

  setup do
    @super_admin = users(:super_admin)
    @company = companies(:enterprise_co)
  end

  test "owner, admin and staff are forbidden" do
    %w[owner admin staff].each do |role|
      member = create_member(@company, role: role)
      get "/api/v1/whatsapp", headers: auth_headers(member, @company)

      assert_response :forbidden, "#{role} should be forbidden"
    end
  end

  test "anonymous requests are unauthorized" do
    get "/api/v1/whatsapp"

    assert_response :unauthorized
  end

  test "super admin reads the state without X-Company-Id" do
    get "/api/v1/whatsapp", headers: auth_headers(@super_admin, nil)

    assert_response :ok
    body = response.parsed_body
    assert_equal "none", body["source"]
    assert_equal "not_connected", body.dig("connection", "status")
    assert_equal %w[verification_code ticket].sort, body["message_types"].map { |t| t["kind"] }.sort
    assert_equal 5, body["tests_remaining"]
    ticket = body["message_types"].find { |t| t["kind"] == "ticket" }
    assert_equal false, ticket["uses_template"]
  end

  test "source is env when only the environment variables exist" do
    with_env("WHATSAPP_ACCESS_TOKEN" => TOKEN, "WHATSAPP_PHONE_NUMBER_ID" => "104512345678901") do
      get "/api/v1/whatsapp", headers: auth_headers(@super_admin, nil)
    end

    assert_equal "env", response.parsed_body["source"]
    assert_equal "104512345678901", response.parsed_body.dig("connection", "phone_number_id")
    assert_not_includes response.body, TOKEN
  end

  test "source is panel once the panel manages the connection, and the key never appears" do
    connection = WhatsappConnection.current
    connection.update!(access_token: TOKEN, phone_number_id: "104512345678901", waba_id: "109876543210987",
                       status: "connected", managed: true)

    with_env("WHATSAPP_ACCESS_TOKEN" => "ENVTOKEN1234", "WHATSAPP_PHONE_NUMBER_ID" => "999999") do
      get "/api/v1/whatsapp", headers: auth_headers(@super_admin, nil)
    end

    assert_response :ok
    body = response.parsed_body
    assert_equal "panel", body["source"]
    assert_equal true, body.dig("connection", "token_present")
    assert_equal "9f3a", body.dig("connection", "token_hint")
    assert_not_includes response.body, TOKEN
    assert_not_includes response.body, "ENVTOKEN1234"
  end

  test "can_enable and blocked_reason explain why a switch is locked" do
    get "/api/v1/whatsapp", headers: auth_headers(@super_admin, nil)

    code = response.parsed_body["message_types"].find { |t| t["kind"] == "verification_code" }
    assert_equal false, code["can_enable"]
    assert_equal "not_connected", code["blocked_reason"]
  end

  test "an old stock_alert row (even a turned-on one) never appears in the state or changes the general switch (spec 048)" do
    ActiveRecord::Base.connection.execute(
      "INSERT INTO whatsapp_message_types (kind, enabled, template_name, template_language, template_status, lock_version, created_at, updated_at) " \
      "VALUES ('stock_alert', TRUE, 'stock_bajo', 'es_MX', 'approved', 0, NOW(), NOW())"
    )

    get "/api/v1/whatsapp", headers: auth_headers(@super_admin, nil)

    assert_response :ok
    assert_equal %w[verification_code ticket].sort, response.parsed_body["message_types"].map { |t| t["kind"] }.sort
    assert_equal false, response.parsed_body.dig("connection", "enabled")
  end

  test "the guide lists only the verification code template, in Spanish and in English" do
    get "/api/v1/whatsapp/guide", headers: auth_headers(@super_admin, nil)

    assert_equal %w[verification_code], response.parsed_body["results"].map { |item| item["kind"] }
    spanish = response.parsed_body["results"].first["body"]
    assert_not_includes response.body, "stock_bajo"

    get "/api/v1/whatsapp/guide", headers: auth_headers(@super_admin, nil).merge("Accept-Language" => "en")
    assert_not_equal spanish, response.parsed_body["results"].first["body"]
  end
end
