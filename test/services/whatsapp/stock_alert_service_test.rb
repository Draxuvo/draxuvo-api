require "test_helper"

class Whatsapp::StockAlertServiceTest < ActiveSupport::TestCase
  ENV_VARS = { "WHATSAPP_ACCESS_TOKEN" => "token-falso", "WHATSAPP_PHONE_NUMBER_ID" => "12345" }.freeze

  FakeHttp = Struct.new(:response, :requests) do
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def request(req)
      requests << req
      response
    end
  end

  def ok_response
    Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, { "messages" => [ { "id" => "wamid.1" } ] }.to_json)
    end
  end

  def error_response
    Net::HTTPBadRequest.new("1.1", "400", "Bad Request").tap do |res|
      res.instance_variable_set(:@read, true)
      res.instance_variable_set(:@body, { "error" => { "message" => "Plantilla no aprobada" } }.to_json)
    end
  end

  def products(count) = Array.new(count) { |index| Product.new(name: "Producto #{index + 1}") }

  def call(env: ENV_VARS, response: ok_response, phone: "5512345678", items: products(2))
    http = FakeHttp.new(response, [])
    result = nil
    with_env(env) do
      Net::HTTP.stub(:new, ->(*) { http }) do
        result = Whatsapp::StockAlertService.new(phone: phone, company_name: "Café Aroma", products: items).call
      end
    end
    [ result, http ]
  end

  test "it sends a template message with the company, the count and the first names" do
    result, http = call(items: products(5))

    assert_equal "sent", result.status
    payload = JSON.parse(http.requests.sole.body)
    assert_equal "template", payload["type"]
    assert_equal "stock_bajo", payload["template"]["name"]
    assert_equal "es_MX", payload["template"]["language"]["code"]
    assert_equal [ "Café Aroma", "5", "Producto 1, Producto 2, Producto 3 (+2)" ],
                 payload["template"]["components"].first["parameters"].map { |parameter| parameter["text"] }
  end

  test "a ten digit Mexican number gets the country code" do
    _, http = call(phone: "55 1234-5678")
    assert_equal "525512345678", JSON.parse(http.requests.sole.body)["to"]
  end

  test "the template name and language come from the environment" do
    _, http = call(env: ENV_VARS.merge("WHATSAPP_STOCK_TEMPLATE_NAME" => "inventario_bajo", "WHATSAPP_STOCK_TEMPLATE_LANG" => "en_US"))
    template = JSON.parse(http.requests.sole.body)["template"]
    assert_equal [ "inventario_bajo", "en_US" ], [ template["name"], template["language"]["code"] ]
  end

  test "without WhatsApp configured it is unavailable and sends nothing" do
    result, http = call(env: { "WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil })
    assert_equal "unavailable", result.status
    assert_empty http.requests
  end

  test "an API error is reported as failed, never raised" do
    result, = call(response: error_response)
    assert_equal "failed", result.status
    assert_equal "Plantilla no aprobada", result.error
  end

  test "in a demo nothing leaves the app" do
    Current.demo = true
    result, http = call
    assert_equal "simulated", result.status
    assert_empty http.requests
  ensure
    Current.reset
  end
end
