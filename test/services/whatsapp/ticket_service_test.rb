require "test_helper"

class Whatsapp::TicketServiceTest < ActiveSupport::TestCase
  ENV_VARS = { "WHATSAPP_ACCESS_TOKEN" => "token-falso", "WHATSAPP_PHONE_NUMBER_ID" => "12345" }.freeze

  FakeHttp = Struct.new(:responses, :requests) do
    attr_accessor :use_ssl, :read_timeout

    def request(req)
      requests << req
      responses.size > 1 ? responses.shift : responses.first
    end
  end

  def response(klass, status, body)
    klass.new("1.1", status, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def ok(body) = response(Net::HTTPOK, "200", body)

  def failure(code, message = "Fuera de ventana") = response(Net::HTTPBadRequest, "400", { "error" => { "code" => code, "message" => message } })

  def with_whatsapp(responses, env: ENV_VARS)
    http = FakeHttp.new(Array(responses), [])
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log)
    out = nil
    result = nil
    with_env(env) do
      Net::HTTP.stub(:new, ->(*) { http }) do
        out, = capture_io { result = yield }
      end
    end
    [ result, http, log.string, out ]
  ensure
    Rails.logger = original_logger
  end

  def ticket = tickets(:pro_paid_ticket)

  def service(phone = "+52 55 1234 5678") = Whatsapp::TicketService.new(ticket, phone: phone)

  test "uploads the PDF and sends it as a document" do
    result, http, = with_whatsapp([ ok({ "id" => "media_1" }), ok({ "messages" => [ { "id" => "wamid.9" } ] }) ]) do
      service.call
    end
    assert_equal "wamid.9", result.dig("messages", 0, "id")
    upload, send = http.requests
    assert_match(%r{/12345/media\z}, upload.path)
    assert_match(/multipart\/form-data; boundary=/, upload["Content-Type"])
    assert_includes upload.body.b, "%PDF".b
    assert_match(%r{/12345/messages\z}, send.path)
    payload = JSON.parse(send.body)
    assert_equal "525512345678", payload["to"]
    assert_equal "document", payload["type"]
    assert_equal "media_1", payload["document"]["id"]
    assert_equal "ticket-#{ticket.folio}.pdf", payload["document"]["filename"]
    assert_includes payload["document"]["caption"], "$500.00"
    assert_equal "Bearer token-falso", send["Authorization"]
  end

  test "falls back to a text message when the 24 hour window is closed" do
    [ 131_026, 131_047 ].each do |code|
      result, http, = with_whatsapp([ ok({ "id" => "media_1" }), failure(code), ok({ "messages" => [ { "id" => "wamid.t" } ] }) ]) do
        service.call
      end
      assert_equal "wamid.t", result.dig("messages", 0, "id")
      assert_equal 3, http.requests.size
      payload = JSON.parse(http.requests.last.body)
      assert_equal "text", payload["type"]
      assert_includes payload["text"]["body"], ticket.folio
      assert_includes payload["text"]["body"], "Total: $500.00 MXN"
      assert_includes payload["text"]["body"], "Lámparas"
    end
  end

  test "the window error on the upload also falls back to text" do
    result, http, = with_whatsapp([ failure(131_047), ok({ "messages" => [ { "id" => "wamid.t" } ] }) ]) { service.call }
    assert_equal "wamid.t", result.dig("messages", 0, "id")
    assert_equal "text", JSON.parse(http.requests.last.body)["type"]
  end

  test "the text fallback says when the order has no items" do
    empty = tickets(:pro_paid_ticket)
    empty.work_order.work_order_items.destroy_all
    _, http, = with_whatsapp([ ok({ "id" => "m" }), failure(131_026), ok({ "messages" => [ { "id" => "w" } ] }) ]) do
      Whatsapp::TicketService.new(empty.reload, phone: "5512345678").call
    end
    assert_includes JSON.parse(http.requests.last.body)["text"]["body"], "sin detalle de items"
  end

  test "other API errors raise with the WhatsApp message" do
    with_whatsapp(failure(100, "Parámetro inválido")) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { service.call }
      assert_equal "Parámetro inválido", error.details
    end
  end

  test "an error without a message uses a generic one" do
    with_whatsapp(response(Net::HTTPInternalServerError, "500", {})) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { service.call }
      assert_includes error.details, "HTTP 500"
    end
  end

  test "missing configuration raises before calling the API" do
    _, http, = with_whatsapp(ok({}), env: { "WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil }) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { service.call }
      assert_equal I18n.t("whatsapp.not_configured"), error.details
      assert_not_includes error.details, "WHATSAPP_"
    end
    assert_empty http.requests
  end

  test "the phone number is cleaned of non digits" do
    _, http, = with_whatsapp([ ok({ "id" => "m" }), ok({ "messages" => [ { "id" => "w" } ] }) ]) { service("(55) 1234-5678").call }
    assert_equal "5512345678", JSON.parse(http.requests.last.body)["to"]
  end

  test "logs go to Rails.logger with a prefix and nothing reaches stdout" do
    _, _, log, out = with_whatsapp([ ok({ "id" => "m" }), ok({ "messages" => [ { "id" => "w" } ] }) ]) { service.call }
    assert_includes log, "[WhatsApp::TicketService] START ticket_id=#{ticket.id}"
    assert_includes log, "SUCCESS message_id=w"
    assert_empty out
  end
end
