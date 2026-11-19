require "test_helper"

# Spec 064: el worker espera a que la API termine de migrar antes de procesar trabajos.
class MigrationWaitTest < ActiveSupport::TestCase
  # Reloj y pausa falsos: pausar avanza el reloj sin dormir de verdad.
  class FakeTime
    attr_reader :now, :pauses

    def initialize
      @now = 0.0
      @pauses = []
    end

    def clock = -> { @now }

    def sleeper
      ->(seconds) { @pauses << seconds; @now += seconds }
    end
  end

  setup do
    @time = FakeTime.new
    @log = StringIO.new
    @logger = Logger.new(@log)
  end

  def wait(pending:, timeout: 600)
    MigrationWait.new(pending: pending, timeout: timeout, interval: 5, clock: @time.clock, sleeper: @time.sleeper,
      logger: @logger).call
  end

  test "returns true without pausing when nothing is pending" do
    assert wait(pending: -> { false })
    assert_empty @time.pauses
    assert_includes @log.string, "[migration_wait] base al día"
    assert_not_includes @log.string, "esperando"
  end

  test "keeps checking every 5 seconds until the pending migrations are gone" do
    answers = [ true, true, false ]
    assert wait(pending: -> { answers.shift })
    assert_equal [ 5, 5 ], @time.pauses
    assert_includes @log.string, "[migration_wait] esperando migraciones…"
    assert_includes @log.string, "[migration_wait] base al día"
  end

  test "returns false at the limit without waiting past it" do
    assert_not wait(pending: -> { true }, timeout: 12)
    assert_equal 12, @time.pauses.sum
    assert_operator @time.now, :<=, 12
    assert_includes @log.string, "[migration_wait] esperando migraciones…"
    assert_not_includes @log.string, "base al día"
  end

  test "for_database reads the limit from MIGRATION_WAIT_SECONDS and defaults to 600" do
    assert_equal 30, MigrationWait.for_database(logger: @logger, env: { "MIGRATION_WAIT_SECONDS" => "30" }).timeout
    assert_equal 600, MigrationWait.for_database(logger: @logger, env: {}).timeout
  end

  test "for_database asks the real database and finds it up to date" do
    assert MigrationWait.for_database(logger: @logger, env: {}).call
  end
end
