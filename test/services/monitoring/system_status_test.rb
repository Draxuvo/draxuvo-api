require "test_helper"

class Monitoring::SystemStatusTest < ActiveSupport::TestCase
  def counting(result)
    calls = 0
    reader = -> { calls += 1; result.respond_to?(:call) ? result.call : result }
    [ reader, -> { calls } ]
  end

  def status(uptime:, errors:, deadline: Monitoring::SystemStatus::EXTERNAL_DEADLINE)
    Monitoring::SystemStatus.call(sources: { uptime: uptime, errors: errors }, deadline: deadline)
  end

  test "builds every card with the internal data" do
    with_memory_cache do
      with_env(RENDER_GIT_COMMIT: "cfe29d1", SENTRY_ENVIRONMENT: "production") do
        result = status(uptime: -> { { state: "ok", monitors: [], heartbeats: [] } }, errors: -> { { state: "ok", projects: [] } })

        assert_equal({ state: "ok", version: "cfe29d1", booted_at: Draxuvo::BOOTED_AT, environment: "production" }, result[:api])
        assert_equal "ok", result[:database][:state]
        assert_kind_of Integer, result[:database][:latency_ms]
        assert_includes %w[ok warn down], result[:jobs][:state]
        assert_equal [ false, nil ], result[:uptime].values_at(:stale, :last_good_at)
        assert_equal "https://draxuvo.sentry.io/issues/", result[:links][:sentry]
      end
    end
  end

  test "external sources are cached for one minute" do
    with_memory_cache do
      uptime, uptime_calls = counting(state: "ok", monitors: [], heartbeats: [])
      errors, errors_calls = counting(state: "ok", projects: [])

      3.times { status(uptime: uptime, errors: errors) }
      assert_equal [ 1, 1 ], [ uptime_calls.call, errors_calls.call ]

      travel 61.seconds do
        status(uptime: uptime, errors: errors)
      end
      assert_equal [ 2, 2 ], [ uptime_calls.call, errors_calls.call ]
    end
  end

  test "a failure after a good read shows the last good copy as stale" do
    with_memory_cache do
      status(uptime: -> { { state: "ok", monitors: [ { name: "API", status: "up" } ], heartbeats: [] } },
             errors: -> { { state: "ok", projects: [] } })

      travel 2.minutes do
        result = status(uptime: -> { { state: "unreachable", reason: "Net::ReadTimeout" } },
                        errors: -> { { state: "unconfigured", reason: "missing_token" } })

        uptime = result[:uptime]
        assert uptime[:stale]
        assert_equal [ "ok", "Net::ReadTimeout", "unreachable" ], uptime.values_at(:state, :reason, :failure_state)
        assert_equal [ { name: "API", status: "up" } ], uptime[:monitors]
        assert_not_nil uptime[:last_good_at]

        assert_equal [ "unconfigured", false ], result[:errors].values_at(:state, :stale)
      end
    end
  end

  test "a hung source does not block the whole snapshot" do
    with_memory_cache do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = status(uptime: -> { sleep 2; { state: "ok" } }, errors: -> { { state: "ok", projects: [] } }, deadline: 0.3)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :<, 1.5
      assert_equal [ "unreachable", "timeout" ], result[:uptime].values_at(:state, :reason)
      assert_equal "ok", result[:errors][:state]
    end
  end
end
