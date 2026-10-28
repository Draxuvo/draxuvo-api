require "test_helper"

class Whatsapp::GraphClientTest < ActiveSupport::TestCase
  TOKEN = "EAAGtokensecreto1234567890".freeze

  FakeHttp = Struct.new(:response, :requests, :error) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      raise error if error

      response
    end
  end

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
    end
  end

  def ok(body = { "id" => "1" }) = http_response(Net::HTTPOK, 200, body)

  def failure_response(code, subcode: nil, message: "msg", http: 400)
    error = { "code" => code, "message" => message }
    error["error_subcode"] = subcode if subcode
    http_response(Net::HTTPBadRequest, http, { "error" => error })
  end

  # Corre el bloque con Net::HTTP simulado y devuelve [resultado, http falso].
  def call(response: ok, error: nil)
    http = FakeHttp.new(response, [], error)
    result = nil
    Net::HTTP.stub(:new, ->(*) { http }) { result = yield Whatsapp::GraphClient.new(token: TOKEN) }
    [ result, http ]
  end

  test "a successful call returns the data and sends the key as a bearer token" do
    result, http = call { |client| client.get("/123", fields: "verified_name") }

    assert result.ok?
    assert_equal({ "id" => "1" }, result.data)
    assert_equal "Bearer #{TOKEN}", http.requests.sole["Authorization"]
    assert_equal "/v25.0/123?fields=verified_name", http.requests.sole.path
  end

  test "post sends JSON and uses short timeouts" do
    result, http = call { |client| client.post("/123/messages", { a: 1 }) }

    assert result.ok?
    request = http.requests.sole
    assert_equal "application/json", request["Content-Type"]
    assert_equal({ "a" => 1 }, JSON.parse(request.body))
    assert_equal [ 3, 5, true ], [ http.open_timeout, http.read_timeout, http.use_ssl ]
  end

  test "post_multipart builds the form with the fields and the file" do
    result, http = call { |client| client.post_multipart("/123/media", fields: { messaging_product: "whatsapp" }, file: { filename: "ticket.pdf", content_type: "application/pdf", bytes: "%PDF-1.4" }) }

    assert result.ok?
    request = http.requests.sole
    assert_match(%r{\Amultipart/form-data; boundary=WhatsApp\h+\z}, request["Content-Type"])
    assert_includes request.body, 'name="messaging_product"'
    assert_includes request.body, 'filename="ticket.pdf"'
    assert_includes request.body, "%PDF-1.4"
  end

  test "190 is a connection failure: expired with subcode 463 and invalid otherwise" do
    expired, = call(response: failure_response(190, subcode: 463)) { |client| client.get("/1") }
    invalid, = call(response: failure_response(190, subcode: 467)) { |client| client.get("/1") }

    assert_equal [ :connection, "token_expired", 190 ], [ expired.failure.family, expired.failure.reason, expired.failure.code ]
    assert_equal [ :connection, "invalid_token" ], [ invalid.failure.family, invalid.failure.reason ]
  end

  test "the connection family covers permissions, restricted accounts and unregistered numbers" do
    { 10 => "missing_permission", 200 => "invalid_token", 299 => "missing_permission", 368 => "account_restricted",
      131_031 => "account_restricted", 133_010 => "invalid_number", 102 => "invalid_token" }.each do |code, reason|
      result, = call(response: failure_response(code)) { |client| client.get("/1") }
      assert_equal [ :connection, reason ], [ result.failure.family, result.failure.reason ], "código #{code}"
      assert result.failure.connection?
    end
  end

  test "the template family covers missing, mismatched and paused templates" do
    { 132_001 => "template_missing", 132_000 => "template_variables", 132_012 => "template_variables",
      132_015 => "template_paused", 132_016 => "template_paused" }.each do |code, reason|
      result, = call(response: failure_response(code)) { |client| client.post("/1/messages", {}) }
      assert_equal [ :template, reason ], [ result.failure.family, result.failure.reason ], "código #{code}"
      assert result.failure.template?
    end
  end

  test "recipient problems are their own family and never look like a connection error" do
    { 131_026 => "recipient_invalid", 131_047 => "outside_24h_window", 131_030 => "not_authorized_recipient" }.each do |code, reason|
      result, = call(response: failure_response(code)) { |client| client.post("/1/messages", {}) }
      assert_equal [ :recipient, reason ], [ result.failure.family, result.failure.reason ]
    end
  end

  test "rate limits and server errors are transient" do
    [ 130_429, 131_048, 80_007, 4 ].each do |code|
      result, = call(response: failure_response(code)) { |client| client.get("/1") }
      assert_equal [ :transient, "rate_limited" ], [ result.failure.family, result.failure.reason ]
    end

    result, = call(response: http_response(Net::HTTPInternalServerError, 500, "no es json")) { |client| client.get("/1") }
    assert_equal [ :transient, "meta_unreachable", 500 ], [ result.failure.family, result.failure.reason, result.failure.http_status ]
    assert result.failure.transient?
  end

  test "timeouts and network errors are transient and do not raise" do
    [ Net::ReadTimeout, Net::OpenTimeout, SocketError, Errno::ECONNREFUSED ].each do |error|
      result, = call(error: error) { |client| client.get("/1") }
      assert_not result.ok?
      assert_equal [ :transient, "meta_unreachable" ], [ result.failure.family, result.failure.reason ], error.name
    end
  end

  test "an unknown rejection is other so the caller can interpret it" do
    result, = call(response: failure_response(100, subcode: 33, message: "Unsupported get request")) { |client| client.get("/1") }

    assert_equal [ :other, "unknown", 100, 33 ], [ result.failure.family, result.failure.reason, result.failure.code, result.failure.subcode ]
  end

  test "the key is never returned in a failure message or written to the logs" do
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    result, = call(response: failure_response(190, message: "Invalid OAuth access token #{TOKEN}")) { |client| client.get("/1") }
    Rails.logger = original

    assert_not_includes result.failure.message, TOKEN
    assert_includes result.failure.message, "[FILTERED]"
    assert_not_includes logged.string, TOKEN
  end
end
