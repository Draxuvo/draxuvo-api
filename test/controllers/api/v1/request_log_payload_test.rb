require "test_helper"

# Spec 071 (US3): cada petición deja en su evento de instrumentación los datos de la línea JSON (contracts/log-line.md)
# sin correo, contraseña ni token.
class RequestLogPayloadTest < ActionDispatch::IntegrationTest
  def capture_payloads
    payloads = []
    callback = ->(*, payload) { payloads << payload }
    ActiveSupport::Notifications.subscribed(callback, "process_action.action_controller") { yield }
    payloads
  end

  test "an authenticated request carries request_id, user, company and demo" do
    owner = users(:pro_co_owner)
    company = companies(:pro_co)

    payload = capture_payloads { get "/api/v1/products", headers: auth_headers(owner, company) }.last

    assert_response :ok
    assert_equal response.headers["X-Request-Id"], payload[:request_id]
    assert_equal owner.id, payload[:user_id]
    assert_equal company.id, payload[:company_id]
    assert_equal false, payload[:demo]
  end

  test "the login line carries no email, password nor token" do
    owner = users(:pro_co_owner)

    payload = capture_payloads do
      post "/api/v1/auth/login", params: { email: owner.email, password: "incorrecta-123" }, as: :json
    end.last
    line = RequestLog.custom_options(Struct.new(:payload).new(payload)).to_json

    assert_nil payload[:user_id]
    assert_nil payload[:company_id]
    assert_not_includes line, owner.email
    assert_not_includes line, "incorrecta-123"
  end
end
