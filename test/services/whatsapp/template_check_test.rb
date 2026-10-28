require "test_helper"

class Whatsapp::TemplateCheckTest < ActiveSupport::TestCase
  TOKEN = "EAAGtokensecreto1234567890".freeze
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

  def http_response(klass, code, body)
    klass.new("1.1", code.to_s, "x").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, body.to_json)
    end
  end

  def template(status: "APPROVED", language: "es_MX", name: "stock_bajo", text: "Stock bajo en {{1}}: {{2}} ({{3}})", reason: nil)
    row = { "name" => name, "language" => language, "status" => status,
            "components" => [ { "type" => "HEADER", "text" => "Hola {{1}}" }, { "type" => "BODY", "text" => text } ] }
    row["rejected_reason"] = reason if reason
    row
  end

  def listing(*rows) = http_response(Net::HTTPOK, 200, "data" => rows)

  def meta_error(code, http: 400)
    http_response(Net::HTTPBadRequest, http, "error" => { "code" => code, "message" => "msg" })
  end

  def check(*responses, name: "stock_bajo", language: "es_MX", expected: 3)
    http = FakeHttp.new(responses, [])
    result = nil
    Net::HTTP.stub(:new, ->(*) { http }) do
      client = Whatsapp::GraphClient.new(token: TOKEN)
      result = Whatsapp::TemplateCheck.new(client: client, waba_id: WABA, name: name, language: language, expected_variables: expected).call
    end
    [ result, http ]
  end

  test "an approved template with the expected variables is approved" do
    result, http = check(listing(template))

    assert_equal "approved", result.status
    assert_nil result.detail
    assert_match "/#{WABA}/message_templates", http.requests.first.path
    assert_match "name=stock_bajo", http.requests.first.path
  end

  test "pending and in-appeal templates are pending" do
    assert_equal "pending", check(listing(template(status: "PENDING"))).first.status
    assert_equal "pending", check(listing(template(status: "IN_APPEAL"))).first.status
  end

  test "rejected, paused and disabled templates are rejected, with the reason when Meta gives one" do
    result, = check(listing(template(status: "REJECTED", reason: "INVALID_FORMAT")))
    assert_equal "rejected", result.status
    assert_equal "REJECTED: INVALID_FORMAT", result.detail

    result, = check(listing(template(status: "PAUSED", reason: "NONE")))
    assert_equal "rejected", result.status
    assert_equal "PAUSED", result.detail

    assert_equal "rejected", check(listing(template(status: "DISABLED"))).first.status
  end

  test "no match is not found" do
    result, = check(listing)

    assert_equal "not_found", result.status
    assert_equal I18n.t("whatsapp_admin.reasons.template_missing"), result.detail
  end

  test "a template in another language is not found and says which languages exist" do
    result, = check(listing(template(language: "en_US")))

    assert_equal "not_found", result.status
    assert_includes result.detail, "en_US"
  end

  test "a different number of variables is incompatible even if approved" do
    result, = check(listing(template(text: "Hola {{1}}")))

    assert_equal "incompatible", result.status
    assert_includes result.detail, "1"
    assert_includes result.detail, "3"
  end

  test "repeated variables count once and only the body counts" do
    result, = check(listing(template(text: "{{1}} {{2}} {{3}} {{1}}")))

    assert_equal "approved", result.status
  end

  test "a template without expected variables (no count to compare) is approved" do
    result, = check(listing(template(text: "Sin variables")), expected: nil)

    assert_equal "approved", result.status
  end

  test "it retries without rejected_reason when Meta does not know that field" do
    result, http = check(meta_error(100), listing(template))

    assert_equal "approved", result.status
    assert_equal 2, http.requests.size
    assert_no_match(/rejected_reason/, http.requests.last.path)
  end

  test "Meta without a response is unreachable and gives no state" do
    result, = check(Net::ReadTimeout)

    assert result.unreachable?
    assert_nil result.status
  end

  test "a connection failure is handed back so Health can record it" do
    result, = check(meta_error(190))

    assert result.failure.connection?
    assert_not result.unreachable?
  end

  test "a blank name is not found without calling Meta" do
    result, http = check(name: "")

    assert_equal "not_found", result.status
    assert_empty http.requests
  end
end
