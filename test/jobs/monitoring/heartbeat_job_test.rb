require "test_helper"

# Spec 071 (US1): el worker manda un latido a Better Stack cada 5 minutos; si deja de llegar, avisa. Sin HEARTBEAT_URL no
# hace nada, y un fallo de red nunca se reintenta ni rompe la cola.
class Monitoring::HeartbeatJobTest < ActiveSupport::TestCase
  URL = "https://uptime.betterstack.com/api/v1/heartbeat/secreto123".freeze

  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout
    attr_reader :requests

    def initialize(error: nil)
      @error = error
      @requests = []
    end

    def request(request)
      raise @error if @error

      @requests << request
      Net::HTTPOK.new("1.1", "200", "OK")
    end
  end

  def with_fake_http(fake)
    hosts = []
    Net::HTTP.stub(:new, ->(host, port) { hosts << [ host, port ]; fake }) { yield hosts }
  end

  test "does nothing without HEARTBEAT_URL" do
    fake = FakeHttp.new
    with_env("HEARTBEAT_URL" => nil) do
      with_fake_http(fake) { |hosts| Monitoring::HeartbeatJob.perform_now; assert_empty hosts }
    end
    assert_empty fake.requests
  end

  test "sends one GET to HEARTBEAT_URL over TLS with 5 second timeouts" do
    fake = FakeHttp.new
    with_env("HEARTBEAT_URL" => URL) do
      with_fake_http(fake) do |hosts|
        Monitoring::HeartbeatJob.perform_now
        assert_equal [ [ "uptime.betterstack.com", 443 ] ], hosts
      end
    end

    assert_equal 1, fake.requests.size
    assert_kind_of Net::HTTP::Get, fake.requests.first
    assert_equal "/api/v1/heartbeat/secreto123", fake.requests.first.path
    assert fake.use_ssl
    assert_equal 5, fake.open_timeout
    assert_equal 5, fake.read_timeout
  end

  test "a network error is logged without the secret URL and is not raised" do
    [ Timeout::Error, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError ].each do |error|
      output = StringIO.new
      logger = ActiveSupport::Logger.new(output)
      with_env("HEARTBEAT_URL" => URL) do
        Rails.stub(:logger, logger) do
          with_fake_http(FakeHttp.new(error: error)) { assert_nothing_raised { Monitoring::HeartbeatJob.perform_now } }
        end
      end

      assert_includes output.string, "[Monitoring::HeartbeatJob]"
      assert_includes output.string, error.name
      assert_not_includes output.string, "secreto123"
    end
  end

  test "is scheduled every 5 minutes in production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    task = recurring.fetch("monitoring_heartbeat")

    assert_equal "Monitoring::HeartbeatJob", task["class"]
    assert_equal "every 5 minutes", task["schedule"]
  end
end
