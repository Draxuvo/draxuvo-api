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
end
