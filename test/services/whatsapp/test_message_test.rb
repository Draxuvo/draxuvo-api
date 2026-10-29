require "test_helper"

class Whatsapp::TestMessageTest < ActiveSupport::TestCase
  TOKEN = "EAAGdelpanel0000".freeze

  FakeHttp = Struct.new(:responses, :requests) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      response = responses.length > 1 ? responses.shift : responses.first
      raise response if response.is_a?(Class) && response <= Exception

      response
    end
  end

  setup do
    WhatsappMessageType.ensure_all!
    WhatsappConnection.current.update!(access_token: TOKEN, phone_number_id: "104512345678901", waba_id: "109876543210987",
                                       status: "connected", managed: true)
  end

  def type(kind) = WhatsappMessageType.find_by!(kind: kind).reload

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def sent = http_response(Net::HTTPOK, 200, "messages" => [ { "id" => "wamid.1" } ])

  def meta_error(code) = http_response(Net::HTTPBadRequest, 400, "error" => { "code" => code, "message" => "msg" })

  def listing(name:, status: "APPROVED", language: "es_MX", text: "{{1}}")
    row = { "name" => name, "language" => language, "status" => status, "components" => [ { "type" => "BODY", "text" => text } ] }
    http_response(Net::HTTPOK, 200, "data" => [ row ])
  end

  # Corre el servicio con Meta simulado: las respuestas se dan en orden (plantilla primero, envío después).
  def send_test(kind, *responses, phone: "5512345678", &after)
    http = FakeHttp.new(responses, [])
    result = nil
    ResendMailer.stub(:whatsapp_alert, ->(**) { { "id" => "m" } }) do
      Net::HTTP.stub(:new, ->(*) { http }) { result = Whatsapp::TestMessage.call(type(kind), phone: phone) }
    end
    after&.call(http)
    [ result, http ]
  end

  def body_of(request) = JSON.parse(request.body)

  test "the verification code test uses 000000 and is sent after re-checking the template" do
    result, http = send_test("verification_code", listing(name: "verification_code"), sent)

    assert result.sent?
    assert_equal 2, http.requests.size
    assert_match "/message_templates", http.requests.first.path
    payload = body_of(http.requests.last)
    assert_equal "template", payload["type"]
    assert_equal "verification_code", payload["template"]["name"]
    assert_equal [ "000000" ], payload["template"]["components"].first["parameters"].map { |p| p["text"] }
    assert_equal "525512345678", payload["to"]
  end

  test "the ticket test is a short text and needs no template" do
    result, http = send_test("ticket", sent)

    assert result.sent?
    assert_equal 1, http.requests.size
    payload = body_of(http.requests.first)
    assert_equal "text", payload["type"]
    assert_equal I18n.t("whatsapp_admin.test.ticket", locale: :es), payload["text"]["body"]
  end

  test "an English template still sends the same test code" do
    type("verification_code").update!(template_language: "en_US")

    _, http = send_test("verification_code", listing(name: "verification_code", language: "en_US"), sent)

    payload = body_of(http.requests.last)
    assert_equal "en_US", payload["template"]["language"]["code"]
    assert_equal [ "000000" ], payload["template"]["components"].first["parameters"].map { |p| p["text"] }
  end

  test "it works with the channel off" do
    assert_not WhatsappConnection.first.enabled?

    result, = send_test("verification_code", listing(name: "verification_code"), sent)

    assert result.sent?
  end

  test "without a connection it is blocked and calls nothing" do
    WhatsappConnection.first.update_columns(status: "not_connected")

    result, http = send_test("ticket", sent)

    assert_equal "blocked", result.status
    assert_equal "not_connected", result.reason
    assert_empty http.requests
  end

  test "a template that is no longer approved is blocked and nothing is sent" do
    result, http = send_test("verification_code", listing(name: "verification_code", status: "PAUSED"))

    assert_equal "blocked", result.status
    assert_equal "template_not_approved", result.reason
    assert_equal 1, http.requests.size
    assert_equal "rejected", type("verification_code").template_status
  end

  test "an incompatible template is blocked" do
    result, = send_test("verification_code", listing(name: "verification_code", text: "{{1}} {{2}}"))

    assert_equal "template_incompatible", result.reason
  end

  test "Meta down while re-checking the template is unreachable and sends nothing" do
    result, http = send_test("verification_code", Net::ReadTimeout)

    assert_equal "unreachable", result.status
    assert_equal 1, http.requests.size
  end

  test "Meta down while sending is unreachable" do
    result, = send_test("ticket", Net::ReadTimeout)

    assert_equal "unreachable", result.status
  end

  test "a recipient that cannot receive it is a failure with its reason and changes no state" do
    result, = send_test("ticket", meta_error(131_030))

    assert_equal "failed", result.status
    assert_equal "not_authorized_recipient", result.reason
    assert_equal 131_030, result.meta_code
    assert_equal "connected", WhatsappConnection.first.status
  end

  test "a key rejected while re-checking the template puts the connection in error" do
    result, = send_test("verification_code", meta_error(190))

    assert_equal "blocked", result.status
    assert_equal "connection_error", result.reason
    assert_equal "error", WhatsappConnection.first.status
  end

  test "in a demo nothing is sent" do
    Current.demo = true

    result, http = send_test("ticket", sent)

    assert_equal "simulated", result.status
    assert_empty http.requests
  ensure
    Current.reset
  end

  test "it never touches the real-send state of the type" do
    type("verification_code").update!(template_status: "approved")
    before = type("verification_code").enabled

    send_test("verification_code", listing(name: "verification_code"), sent)

    assert_equal before, type("verification_code").enabled
  end
end
