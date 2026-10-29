require "test_helper"

# Spec 047, US3: cuándo salen de verdad los mensajes y qué pasa cuando Meta falla en un envío real. Meta se simula.
class Whatsapp::ChannelBehaviorTest < ActiveSupport::TestCase
  TOKEN = "EAAGdelpanel0000".freeze
  ENV_VARS = { "WHATSAPP_ACCESS_TOKEN" => "token-de-entorno", "WHATSAPP_PHONE_NUMBER_ID" => "12345" }.freeze
  NO_ENV = { "WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil }.freeze
  Product = Struct.new(:name)
  Ticket = Struct.new(:id, :folio)

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
    %w[verification_code].each { |kind| type(kind).update!(template_status: "approved") }
    WhatsappConnection.current.update!(enabled: true)
    %w[verification_code ticket].each { |kind| type(kind).update!(enabled: true) }
    @mails = []
    @mailer = ->(user:, problem:, target:, **) { @mails << { to: user.email, problem: problem, target: target }; { "id" => "m" } }
  end

  def connection = WhatsappConnection.current.reload

  def type(kind) = WhatsappMessageType.find_by!(kind: kind).reload

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def ok = http_response(Net::HTTPOK, 200, "messages" => [ { "id" => "wamid.1" } ])

  def meta_error(code, http: 400) = http_response(Net::HTTPBadRequest, http, "error" => { "code" => code, "message" => "msg" })

  # Corre el bloque con Meta simulado; devuelve las peticiones hechas.
  def with_meta(*responses, env: NO_ENV)
    http = FakeHttp.new(responses.presence || [ ok ], [])
    with_env(env) do
      Net::HTTP.stub(:new, ->(*) { http }) do
        ResendMailer.stub(:whatsapp_alert, @mailer) { yield }
      end
    end
    http.requests
  end


  # Manda un código de verificación y dice qué pasó: "sent", "unavailable" (canal no disponible, como siempre) o "failed" (Meta lo rechazó).
  def send_code
    Whatsapp::OtpService.new("5512345678").send_code
    "sent"
  rescue ApiErrors::UnprocessableEntityError => e
    e.details == unavailable_message ? "unavailable" : "failed"
  end

  def send_ticket = Whatsapp::TicketService.new(Ticket.new(1, "T-000001"), phone: "5512345678").call

  def unavailable_message = I18n.t("whatsapp.not_configured")

  def assert_unavailable(&block)
    error = assert_raises(ApiErrors::UnprocessableEntityError, &block)
    assert_equal unavailable_message, error.details
  end

  test "everything on and the template approved: the verification code goes out" do
    requests = with_meta { assert_equal "sent", send_code }

    assert_equal 1, requests.size
  end

  test "with the general switch off nothing goes out and the services answer unavailable as always" do
    connection.update!(enabled: false)

    requests = with_meta do
      assert_equal "unavailable", send_code
      assert_unavailable { send_ticket }
    end

    assert_empty requests
  end

  test "with one type off only that type stops" do
    type("verification_code").update!(enabled: false)

    requests = with_meta { assert_equal "unavailable", send_code }

    assert_empty requests
    assert type("ticket").enabled
    assert Whatsapp::Config.current.available?("ticket"), "el otro tipo sigue disponible"
    assert_not Whatsapp::Config.current.available?("verification_code")
  end

  test "a template that is not approved keeps its type unavailable" do
    type("verification_code").update_columns(template_status: "rejected")

    requests = with_meta { assert_equal "unavailable", send_code }

    assert_empty requests
  end

  test "a demo company simulates the messages even with everything on" do
    Current.demo = true

    requests = with_meta do
      assert_equal "sent", send_code # en demo el código es fijo y no sale nada
      assert_equal({ "demo" => true }, send_ticket)
    end

    assert_empty requests
  ensure
    Current.reset
  end

  test "the retired low stock template variables and type do nothing (spec 048)" do
    type_count = WhatsappMessageType.count
    requests = with_meta(env: ENV_VARS.merge("WHATSAPP_STOCK_TEMPLATE_NAME" => "otra")) { assert_equal "sent", send_code }

    assert_equal 1, requests.size
    assert_equal type_count, WhatsappMessageType.count
  end

  test "a key rejected by Meta in a real send puts the connection in error and warns once; later sends stop and do not warn again" do
    requests = with_meta(meta_error(190)) do
      assert_equal "failed", send_code
      assert_equal "unavailable", send_code
    end

    assert_equal 1, requests.size
    assert_equal "error", connection.status
    assert_equal 1, @mails.count { |mail| mail[:problem] == "connection" }
  end

  test "once the connection recovers, the next failure warns again" do
    with_meta(meta_error(190)) { send_code }
    assert_equal "error", connection.status
    first = @mails.count { |mail| mail[:problem] == "connection" }

    connection.update!(status: "connected") # «Verificar ahora» la dejó bien
    Whatsapp::Health.connection_recovered!
    with_meta(meta_error(190)) { send_code }

    assert_equal first + 1, @mails.count { |mail| mail[:problem] == "connection" }
  end

  test "a successful send clears a connection error" do
    with_meta(meta_error(190)) { send_code }
    assert_equal "error", connection.status

    connection.update_columns(status: "connected")
    with_meta { send_code }

    assert_equal "connected", connection.status
    assert_nil connection.problem_notified_at
  end

  test "a template rejected in a real send turns off only that type" do
    with_meta(meta_error(132_001)) { assert_equal "failed", send_code }

    assert_not type("verification_code").enabled
    assert_equal "not_found", type("verification_code").template_status
    assert type("ticket").enabled
    assert connection.enabled
    assert_equal 1, @mails.count { |mail| mail[:problem] == "template" && mail[:target] == "verification_code" }
  end

  test "a failure of the recipient or of the network changes nothing" do
    with_meta(meta_error(131_030)) { send_code }
    with_meta(Net::ReadTimeout) { send_code }
    with_meta(meta_error(130_429)) { send_code }

    assert_equal "connected", connection.status
    assert type("verification_code").enabled
    assert_empty @mails
  end

  test "the environment variables keep working while the panel was never used" do
    WhatsappConnection.delete_all
    WhatsappMessageType.delete_all

    requests = with_meta(env: ENV_VARS) do
      assert_equal :env, Whatsapp::Config.current.source
      assert_equal "sent", send_code
    end

    assert_equal 1, requests.size
  end

  test "once the panel was used the environment variables are ignored, even after disconnecting" do
    connection.disconnect!

    requests = with_meta(env: ENV_VARS) do
      assert_equal :panel, Whatsapp::Config.current.source
      assert_equal "unavailable", send_code
    end

    assert_empty requests
  end
end
