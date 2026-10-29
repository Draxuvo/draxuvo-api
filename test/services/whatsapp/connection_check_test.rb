require "test_helper"

class Whatsapp::ConnectionCheckTest < ActiveSupport::TestCase
  TOKEN = "EAAGtokensecreto1234567890".freeze
  PHONE = "104512345678901".freeze
  WABA = "109876543210987".freeze

  # Responde en orden a cada petición que haga el verificador.
  FakeHttp = Struct.new(:responses, :requests) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      response = responses.shift
      raise response if response.is_a?(Class) && response <= Exception

      response
    end
  end

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def ok(body) = http_response(Net::HTTPOK, 200, body)

  def meta_error(code, subcode: nil, http: 400)
    error = { "code" => code, "message" => "msg" }
    error["error_subcode"] = subcode if subcode
    http_response(Net::HTTPBadRequest, http, { "error" => error })
  end

  def phone_ok = ok("verified_name" => "Draxuvo", "display_phone_number" => "+52 55 1234 5678", "id" => PHONE)

  def numbers_ok(*ids) = ok("data" => ids.map { |id| { "id" => id } })

  def check(*responses, phone: PHONE, waba: WABA)
    http = FakeHttp.new(responses, [])
    result = nil
    Net::HTTP.stub(:new, ->(*) { http }) do
      result = Whatsapp::ConnectionCheck.new(token: TOKEN, phone_number_id: phone, waba_id: waba).call
    end
    [ result, http ]
  end

  test "a Meta test account that cannot list its numbers is accepted and flagged as a test account" do
    # Respuesta real de Meta (2026-10-28): 100 con subcódigo 2388339, «API no soportada para esta cuenta».
    result, = check(phone_ok, meta_error(100, subcode: 2_388_339))

    assert result.ok?
    assert result.test_account?
    assert_equal "Draxuvo", result.verified_name
    assert_equal "+52 55 1234 5678", result.display_phone_number
  end

  test "a regular account is not flagged as a test account" do
    result, = check(phone_ok, numbers_ok(PHONE))

    assert result.ok?
    assert_not result.test_account?
  end

  test "a plain 100 on the account (no access or does not exist) is still rejected" do
    result, = check(phone_ok, meta_error(100, subcode: 33))

    assert_not result.ok?
    assert_equal "account_not_found", result.reason
  end

  test "a plain 100 on the number says the key may have no access, not only that the id is wrong" do
    result, = check(meta_error(100, subcode: 33))

    assert_equal "invalid_number", result.reason
    assert_match(/no tiene acceso/, result.message)
  end

  test "a valid key, number and account are accepted with the visible name and number" do
    result, http = check(phone_ok, numbers_ok("1", PHONE))

    assert result.ok?
    assert_equal "Draxuvo", result.verified_name
    assert_equal "+52 55 1234 5678", result.display_phone_number
    assert_equal 2, http.requests.size
    assert_match "/#{PHONE}", http.requests.first.path
    assert_match "/#{WABA}/phone_numbers", http.requests.last.path
  end

  test "an invalid key is rejected with its reason and Meta code" do
    result, = check(meta_error(190))

    assert_not result.ok?
    assert_equal "invalid_token", result.reason
    assert_equal 190, result.meta_code
  end

  test "an expired key is told apart from an invalid one" do
    result, = check(meta_error(190, subcode: 463))

    assert_equal "token_expired", result.reason
  end

  test "a key without permission is rejected" do
    result, = check(meta_error(10))

    assert_equal "missing_permission", result.reason
  end

  test "a number that does not exist is rejected as an invalid number" do
    result, = check(meta_error(100))

    assert_equal "invalid_number", result.reason
  end

  test "a number that is not in the account is rejected" do
    result, = check(phone_ok, numbers_ok("999"))

    assert_equal "phone_not_in_account", result.reason
  end

  test "an account that does not exist is rejected" do
    result, = check(phone_ok, meta_error(100))

    assert_equal "account_not_found", result.reason
  end

  test "malformed identifiers are rejected without calling Meta" do
    result, http = check(phone: "12ab")
    assert_equal "invalid_number", result.reason

    result, = check(waba: "x")
    assert_equal "account_not_found", result.reason
    assert_empty http.requests
  end

  test "Meta without a response is unreachable, not a rejection" do
    result, = check(Net::ReadTimeout)

    assert_not result.ok?
    assert result.unreachable?
  end

  test "a Meta server error is unreachable" do
    result, = check(http_response(Net::HTTPInternalServerError, 500, {}))

    assert result.unreachable?
  end

  test "the rejection message is in Spanish and never carries the key" do
    result, = check(meta_error(190))

    assert_equal I18n.t("whatsapp_admin.reasons.invalid_token"), result.message
    assert_not_includes result.message, TOKEN
  end
end
