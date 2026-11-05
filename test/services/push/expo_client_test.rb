require "test_helper"

class Push::ExpoClientTest < ActiveSupport::TestCase
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

  def with_http(*responses)
    http = FakeHttp.new(responses, [])
    Net::HTTP.stub(:new, ->(*) { http }) { yield }
    http
  end

  def messages(count) = Array.new(count) { |i| { to: "ExponentPushToken[t#{i}]", title: "T", body: "B" } }

  def ok_tickets(count) = { "data" => Array.new(count) { |i| { "status" => "ok", "id" => "id-#{i}" } } }

  test "sends in batches of 100 and returns the tickets in order" do
    tickets = nil
    http = with_http(http_response(Net::HTTPOK, 200, ok_tickets(100)), http_response(Net::HTTPOK, 200, ok_tickets(20))) do
      tickets = Push::ExpoClient.new.send_messages(messages(120))
    end

    assert_equal 2, http.requests.size
    assert_equal 100, JSON.parse(http.requests.first.body).size
    assert_equal 120, tickets.size
    assert_equal 3, http.open_timeout
    assert_nil http.requests.first["Authorization"], "sin EXPO_ACCESS_TOKEN no se manda llave"
  end

  test "uses EXPO_ACCESS_TOKEN when present" do
    http = with_env("EXPO_ACCESS_TOKEN" => "secret") do
      with_http(http_response(Net::HTTPOK, 200, ok_tickets(1))) { Push::ExpoClient.new.send_messages(messages(1)) }
    end

    assert_equal "Bearer secret", http.requests.first["Authorization"]
  end

  test "rate limits, server errors and network failures are transient" do
    [ http_response(Net::HTTPTooManyRequests, 429, {}), http_response(Net::HTTPBadGateway, 502, {}), Net::OpenTimeout ].each do |response|
      with_http(response) do
        assert_raises(Push::ExpoClient::Transient) { Push::ExpoClient.new.send_messages(messages(1)) }
      end
    end
  end

  test "a per-message error comes back in its ticket" do
    body = { "data" => [ { "status" => "error", "message" => "x", "details" => { "error" => "DeviceNotRegistered" } } ] }
    tickets = nil
    with_http(http_response(Net::HTTPOK, 200, body)) { tickets = Push::ExpoClient.new.send_messages(messages(1)) }

    assert_equal "DeviceNotRegistered", tickets.first.dig("details", "error")
  end
end
