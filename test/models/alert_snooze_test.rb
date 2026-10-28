require "test_helper"

class AlertSnoozeTest < ActiveSupport::TestCase
  def snooze(**attrs)
    AlertSnooze.new({ company: companies(:resto_co), kind: "table_open", subject_key: "check:1:t:1", snoozed_until: 1.hour.from_now }.merge(attrs))
  end

  test "only time alerts can be snoozed, never low stock" do
    assert snooze.valid?
    assert_not snooze(kind: "low_stock").valid?
    assert_not snooze(kind: "other").valid?
  end

  test "the same element is snoozed once per company and kind" do
    snooze.save!
    assert_raises(ActiveRecord::RecordNotUnique) { snooze.save!(validate: false) }
    assert snooze(company: companies(:one)).valid?
  end

  test "active and expired split by the deadline" do
    live = snooze.tap(&:save!)
    old = snooze(subject_key: "check:2:t:1", snoozed_until: 1.minute.ago).tap { |s| s.save!(validate: false) }
    assert_includes AlertSnooze.active, live
    assert_includes AlertSnooze.expired, old
    assert_not_includes AlertSnooze.active, old
  end
end
