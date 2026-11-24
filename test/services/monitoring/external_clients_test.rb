require "test_helper"

# Spec 073: clientes de Better Stack y Sentry del estado del sistema. La red se simula con `http:`.
class Monitoring::ExternalClientsTest < ActiveSupport::TestCase
  TOKEN = "token-super-secreto".freeze
  Response = Monitoring::ExternalSource::Response

  def capture_logs
    logs = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logs)
    yield
    logs.string
  ensure
    Rails.logger = original
  end

  def better_stack(responses, token: TOKEN)
    calls = []
    http = ->(uri, headers) { calls << [ uri, headers ]; responses.fetch(uri.path) }
    result = with_env(BETTERSTACK_UPTIME_TOKEN: token, BETTERSTACK_TEAM_ID: "t9") { Monitoring::BetterStackClient.call(http: http) }
    [ result, calls ]
  end

  def sentry(response, token: TOKEN)
    calls = []
    http = ->(uri, headers) { calls << [ uri, headers ]; response.is_a?(Exception) ? raise(response) : response }
    result = with_env(SENTRY_API_TOKEN: token) { Monitoring::SentryClient.call(http: http) }
    [ result, calls ]
  end

  MONITORS = { "data" => [
    { "id" => "11", "attributes" => { "pronounceable_name" => "Draxuvo API", "url" => "https://api.draxuvo.com/up",
                                      "status" => "up", "last_checked_at" => "2026-11-24T18:00:00Z" } },
    { "id" => "12", "attributes" => { "pronounceable_name" => "Draxuvo sitio", "url" => "https://draxuvo.com/es", "status" => "down" } }
  ] }.to_json
  HEARTBEATS = { "data" => [ { "id" => "21", "attributes" => { "name" => "Trabajos", "status" => "up" } } ] }.to_json

  test "better stack without a token does not call anyone" do
    result, calls = better_stack({}, token: nil)
    assert_equal({ state: "unconfigured", reason: "missing_token" }, result)
    assert_empty calls
  end

  test "better stack maps monitors and heartbeats and sends the token only in the header" do
    result, calls = better_stack({ "/api/v2/monitors" => Response.new(200, MONITORS), "/api/v2/heartbeats" => Response.new(200, HEARTBEATS) })

    assert_equal "down", result[:state]
    assert_equal({ name: "Draxuvo API", url: "https://api.draxuvo.com/up", status: "up", last_checked_at: "2026-11-24T18:00:00Z",
                   link: "https://uptime.betterstack.com/team/t9/monitors/11" }, result[:monitors].first)
    assert_equal({ name: "Trabajos", status: "up", link: "https://uptime.betterstack.com/team/t9/heartbeats/21" }, result[:heartbeats].first)
    assert_equal 2, calls.size
    assert_equal "Bearer #{TOKEN}", calls.first.last["Authorization"]
    assert_not_includes result.to_json, TOKEN
  end

  test "better stack states for rejected tokens and errors" do
    rejected, = better_stack({ "/api/v2/monitors" => Response.new(401, "{}") })
    assert_equal "invalid_token", rejected[:state]

    down, = better_stack({ "/api/v2/monitors" => Response.new(503, "") })
    assert_equal({ state: "unreachable", reason: "http_503" }, down)
  end

  test "sentry groups issues by project, keeps the five newest and logs without the token" do
    issues = Array.new(7) { |i| { "title" => "Error #{i}", "count" => "#{i + 1}", "lastSeen" => "2026-11-24T1#{i}:00:00Z",
                                  "permalink" => "https://draxuvo.sentry.io/issues/#{i}/", "project" => { "slug" => "draxuvo-api" } } }
    issues << { "title" => "Panel", "count" => "2", "project" => { "slug" => "draxuvo-ui" } }

    logs = capture_logs do
      @result, @calls = sentry(Response.new(200, issues.to_json))
    end

    assert_equal "warn", @result[:state]
    assert_equal %w[draxuvo-api draxuvo-ui draxuvo-web draxuvo-app], @result[:projects].map { |project| project[:slug] }
    api = @result[:projects].first
    assert_equal [ 7, false, 5 ], [ api[:unresolved], api[:capped], api[:issues].size ]
    assert_equal({ title: "Error 0", count: 1, last_seen: "2026-11-24T10:00:00Z", link: "https://draxuvo.sentry.io/issues/0/" }, api[:issues].first)
    assert_equal 0, @result[:projects].last[:unresolved]

    uri = @calls.first.first
    assert_equal "/api/0/organizations/draxuvo/issues/", uri.path
    assert_includes uri.query, "query=is%3Aunresolved"
    assert_includes uri.query, "statsPeriod=24h"
    assert_includes logs, "[Monitoring::SentryClient] warn"
    assert_not_includes logs, TOKEN
  end

  test "sentry is ok without issues and marks the list as capped at 100" do
    ok, = sentry(Response.new(200, "[]"))
    assert_equal "ok", ok[:state]

    many = Array.new(100) { { "title" => "x", "count" => "1", "project" => { "slug" => "draxuvo-web" } } }
    capped, = sentry(Response.new(200, many.to_json))
    assert capped[:projects].all? { |project| project[:capped] }
  end

  test "sentry timeouts and rejected tokens" do
    timeout, = sentry(Net::ReadTimeout.new)
    assert_equal({ state: "unreachable", reason: "Net::ReadTimeout" }, timeout)

    forbidden, = sentry(Response.new(403, "{}"))
    assert_equal "invalid_token", forbidden[:state]

    missing, = sentry(nil, token: "")
    assert_equal "unconfigured", missing[:state]
  end
end
