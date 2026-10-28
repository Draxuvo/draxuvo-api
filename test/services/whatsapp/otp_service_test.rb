require "test_helper"

class Whatsapp::OtpServiceTest < ActiveSupport::TestCase
  ENV_VARS = { "WHATSAPP_ACCESS_TOKEN" => "token-falso", "WHATSAPP_PHONE_NUMBER_ID" => "12345" }.freeze

  FakeHttp = Struct.new(:response, :requests) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      response
    end
  end

  def ok_response(body = { "messages" => [ { "id" => "wamid.1" } ] })
    Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def error_response(message: "Token inválido", code: 190)
    Net::HTTPBadRequest.new("1.1", "400", "Bad Request").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, { "error" => { "message" => message, "code" => code } }.to_json)
    end
  end

  # Corre el bloque con ENV de WhatsApp, caché en memoria, Net::HTTP simulado y el logger en un StringIO.
  def with_whatsapp(response = ok_response, env: ENV_VARS)
    http = FakeHttp.new(response, [])
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log)
    out = nil
    with_env(env) do
      with_memory_cache do |cache|
        Net::HTTP.stub(:new, ->(*) { http }) do
          out, = capture_io { yield http, cache }
        end
      end
    end
    [ http, log.string, out ]
  ensure
    Rails.logger = original_logger
  end

  test "send_code returns a 6 digit code, stores it and posts the template" do
    code = nil
    http, = with_whatsapp do |_http, cache|
      code = Whatsapp::OtpService.new("+52 (55) 1234-5678").send_code
      assert_equal code, cache.read("whatsapp_otp:525512345678")
    end
    assert_match(/\A\d{6}\z/, code)
    assert_equal 1, http.requests.size
    request = http.requests.first
    assert_equal "Bearer token-falso", request["Authorization"]
    payload = JSON.parse(request.body)
    assert_equal "525512345678", payload["to"]
    assert_equal "verification_code", payload["template"]["name"]
    assert_equal code, payload["template"]["components"].first["parameters"].first["text"]
  end

  test "the template name and language come from ENV" do
    http, = with_whatsapp(env: ENV_VARS.merge("WHATSAPP_OTP_TEMPLATE_NAME" => "mi_codigo",
                                              "WHATSAPP_OTP_TEMPLATE_LANG" => "en_US")) do
      Whatsapp::OtpService.new("5512345678").send_code
    end
    template = JSON.parse(http.requests.first.body)["template"]
    assert_equal "mi_codigo", template["name"]
    assert_equal "en_US", template["language"]["code"]
  end

  test "verify accepts the right code once" do
    with_whatsapp do |_http, cache|
      service = Whatsapp::OtpService.new("5512345678")
      code = service.send_code
      assert_equal({ verified: true }, service.verify(" #{code} "))
      assert_nil cache.read("whatsapp_otp:5512345678")
      result = service.verify(code)
      assert_not result[:verified]
      assert_includes result[:error], "expiró"
    end
  end

  test "verify rejects a wrong code and keeps the stored one" do
    with_whatsapp do |_http, cache|
      service = Whatsapp::OtpService.new("5512345678")
      code = service.send_code
      wrong = code == "000000" ? "111111" : "000000"
      result = service.verify(wrong)
      assert_equal({ verified: false, error: "Código incorrecto." }, result)
      assert_equal code, cache.read("whatsapp_otp:5512345678")
    end
  end

  test "verify reports an expired or unknown code" do
    with_whatsapp do |_http, cache|
      service = Whatsapp::OtpService.new("5512345678")
      assert_not service.verify("123456")[:verified]
      code = service.send_code
      cache.delete("whatsapp_otp:5512345678")
      assert_not service.verify(code)[:verified]
    end
  end

  test "the stored code expires after ten minutes" do
    with_whatsapp do |_http, cache|
      service = Whatsapp::OtpService.new("5512345678")
      service.send_code
      travel_to 11.minutes.from_now do
        assert_nil cache.read("whatsapp_otp:5512345678")
      end
    end
  end

  test "codes are scoped to the cleaned phone number" do
    with_whatsapp do |_http, cache|
      Whatsapp::OtpService.new("55-1234-5678").send_code
      assert cache.exist?("whatsapp_otp:5512345678")
      assert_not Whatsapp::OtpService.new("5599999999").verify("123456")[:verified]
    end
  end

  test "missing configuration raises and sends nothing" do
    http, = with_whatsapp(env: { "WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => "" }) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { Whatsapp::OtpService.new("5512345678").send_code }
      assert_equal I18n.t("whatsapp.not_configured"), error.details
      assert_not_includes error.details, "WHATSAPP_"
    end
    assert_empty http.requests
  end

  test "an API error raises with the message from WhatsApp" do
    with_whatsapp(error_response) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { Whatsapp::OtpService.new("5512345678").send_code }
      assert_equal "Token inválido", error.details
    end
  end

  test "an API error without a message falls back to a generic one" do
    response = error_response
    response.instance_variable_set(:@body, "{}")
    with_whatsapp(response) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { Whatsapp::OtpService.new("5512345678").send_code }
      assert_includes error.details, "HTTP 400"
    end
  end

  test "logs go to Rails.logger with a prefix, never to stdout, and never include the code" do
    code = nil
    _, log, out = with_whatsapp { code = Whatsapp::OtpService.new("5512345678").send_code }
    assert_includes log, "[Whatsapp::OtpService] OTP sent phone=5512345678"
    assert_empty out
    assert_not_includes log.sub(/"text":"#{code}"/, ""), "otp=#{code}"
  end
end
