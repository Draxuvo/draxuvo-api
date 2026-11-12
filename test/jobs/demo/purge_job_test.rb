require "test_helper"

class Demo::PurgeJobTest < ActiveJob::TestCase
  def open_demo(**extra) = Demo::Provision.call(plan: "basic", scenario: "basic_retail", locale: "es", **extra)

  test "purges expired demos and leaves the active ones" do
    expired = open_demo
    active = open_demo
    expired.session.update_columns(expires_at: 5.minutes.ago)

    Demo::PurgeJob.perform_now

    assert_not Company.exists?(expired.company.id)
    assert Company.exists?(active.company.id)
    assert expired.session.reload.purged_at
    assert_nil active.session.reload.purged_at
  end

  test "purges the demos the visitor already ended" do
    ended = open_demo
    ended.session.update!(ended_at: Time.current, ended_reason: "left")

    Demo::PurgeJob.perform_now

    assert_not Company.exists?(ended.company.id)
  end

  test "works in batches of 20 and is idempotent" do
    demos = Array.new(3) { open_demo }
    demos.each { |demo| demo.session.update_columns(expires_at: 1.minute.ago) }

    Demo::PurgeJob.perform_now(batch_size: 2)
    assert_equal 1, DemoSession.where(purged_at: nil).count { |session| demos.map { |d| d.session.id }.include?(session.id) }

    Demo::PurgeJob.perform_now
    Demo::PurgeJob.perform_now
    assert demos.all? { |demo| demo.session.reload.purged_at }
  end

  test "purges only the given company when it receives one" do
    one = open_demo
    other = open_demo
    [ one, other ].each { |demo| demo.session.update!(ended_at: Time.current, ended_reason: "left") }

    Demo::PurgeJob.perform_now(company_id: one.company.id)

    assert_not Company.exists?(one.company.id)
    assert Company.exists?(other.company.id)
  end

  test "never touches real companies" do
    real = companies(:pro_co)

    assert_no_difference -> { Company.real.count } do
      Demo::PurgeJob.perform_now
    end
    assert Company.exists?(real.id)
  end

  # Spec 062: «Salir de la demo» después de cobrar algo (el dueño quedó con llaves de idempotencia).
  test "purges the given company even when its owner left idempotency keys" do
    demo = open_demo
    demo.session.update!(ended_at: Time.current, ended_reason: "left")
    idempotency_key_for(demo.user)

    Demo::PurgeJob.perform_now(company_id: demo.company.id)

    assert_not Company.exists?(demo.company.id)
    assert demo.session.reload.purged_at
  end


  # Spec 062 (US2): una demo que falla no detiene a las demás, queda intacta, marcada y con su error en el log.
  test "a demo that fails is left intact, marked and logged while the others are purged" do
    first, failing, last = Array.new(3) { open_demo }
    [ first, failing, last ].each_with_index { |demo, i| demo.session.update_columns(expires_at: (30 - i).minutes.ago) }

    log = with_captured_log { failing_purge(failing.company) { Demo::PurgeJob.perform_now } }

    assert_not Company.exists?(first.company.id)
    assert_not Company.exists?(last.company.id)
    assert Company.exists?(failing.company.id)
    assert_nil failing.session.reload.purged_at
    assert failing.session.purge_failed_at
    assert_match(/\[Demo::PurgeJob\] company=#{failing.company.id} session=#{failing.session.id}: RuntimeError: falla simulada/, log)
  end

  test "demos that keep failing go to the back of the batch" do
    stuck = open_demo
    healthy = open_demo
    stuck.session.update_columns(expires_at: 1.hour.ago)
    healthy.session.update_columns(expires_at: 5.minutes.ago)

    failing_purge(stuck.company) do
      Demo::PurgeJob.perform_now(batch_size: 1)
      assert stuck.session.reload.purge_failed_at
      assert Company.exists?(healthy.company.id)

      Demo::PurgeJob.perform_now(batch_size: 1)
    end

    assert_not Company.exists?(healthy.company.id)
    assert Company.exists?(stuck.company.id)
  end

  test "a demo that failed before is purged once it stops failing" do
    demo = open_demo
    demo.session.update_columns(expires_at: 5.minutes.ago, purge_failed_at: 10.minutes.ago)

    Demo::PurgeJob.perform_now

    assert_not Company.exists?(demo.company.id)
    assert demo.session.reload.purged_at
  end

  test "a failing purge of a given company does not raise and leaves it for the periodic run" do
    demo = open_demo
    demo.session.update!(ended_at: Time.current, ended_reason: "left")

    log = with_captured_log do
      failing_purge(demo.company) { assert_nothing_raised { Demo::PurgeJob.perform_now(company_id: demo.company.id) } }
    end

    assert Company.exists?(demo.company.id)
    assert demo.session.reload.purge_failed_at
    assert_includes DemoSession.purgeable, demo.session
    assert_match(/\[Demo::PurgeJob\] company=#{demo.company.id}/, log)
  end

  # Spec 062 (US3): el atraso, con demos con y sin llaves, se limpia en varias corridas.
  test "a backlog of expired demos, some with idempotency keys, is cleared over several runs" do
    demos = Array.new(5) { open_demo }
    demos.each { |demo| demo.session.update_columns(expires_at: 1.day.ago) }
    demos.first(2).each { |demo| idempotency_key_for(demo.user) }

    3.times { Demo::PurgeJob.perform_now(batch_size: 2) }

    sessions = demos.map { |demo| demo.session.reload }
    assert sessions.all?(&:purged_at)
    assert sessions.none?(&:purge_failed_at)
  end

  private

  def idempotency_key_for(user, key = "cobro-1")
    IdempotencyKey.create!(user: user, key: key, request_method: "POST", request_path: "/api/v1/sales/1/charge",
                           response_status: 200, response_body: "{}")
  end

  # Hace fallar la purga de una empresa y deja pasar las demás.
  def failing_purge(company)
    original = Demo::Purge.method(:call)
    fake = ->(target) { target.id == company.id ? raise("falla simulada") : original.call(target) }
    Demo::Purge.stub(:call, fake) { yield }
  end

  def with_captured_log
    io = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = previous
  end
end
