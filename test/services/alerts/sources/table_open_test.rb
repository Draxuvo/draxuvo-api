require "test_helper"

class Alerts::Sources::TableOpenTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    Product.where(company_id: @company.id).update_all(stock: 1000) # que el stock bajo no mezcle las cuentas
  end

  def alerts = Alerts::Collector.new(@company).call.results.select { |alert| alert.kind == "table_open" }

  def open_ago(minutes, check: checks(:open_check)) = Check.where(id: check.id).update_all(opened_at: minutes.minutes.ago)

  test "a table check open longer than the limit alerts with the waiter and the total" do
    assert_empty alerts

    open_ago(190)
    alert = alerts.sole
    assert_equal [ 190, 90, "critical" ], [ alert.minutes, alert.threshold_minutes, alert.severity ]
    assert_equal "Mesa 1", alert.subject[:label]
    assert_equal checks(:open_check).id, alert.subject[:check_id]
    assert_equal({ type: "waiter", name: checks(:open_check).waiter.full_name }, alert.owner)
    assert_equal "155.00", alert.total
    assert_match(/\Acheck:\d+:t:\d+\z/, alert.subject_key)
  end

  test "just under the limit it is a warning once over and below twice the limit" do
    open_ago(100)
    assert_equal "warning", alerts.sole.severity
    open_ago(80)
    assert_empty alerts
  end

  test "takeout checks do not count as tables, and closed or cancelled ones disappear" do
    open_ago(500, check: checks(:takeout_check))
    assert_empty alerts

    open_ago(190)
    assert_equal 1, alerts.size
    Check.where(id: checks(:open_check).id).update_all(status: 1, closed_at: Time.current)
    assert_empty alerts
  end

  test "a table that is occupied again is a different alert and does not inherit the snooze" do
    open_ago(190)
    first_key = alerts.sole.subject_key
    @company.alert_snoozes.create!(kind: "table_open", subject_key: first_key, snoozed_until: 1.hour.from_now)
    assert_empty alerts

    open_ago(130)
    assert_not_equal first_key, alerts.sole.subject_key
  end

  test "a custom limit and a missing restaurant module are respected" do
    open_ago(40)
    AlertSetting.create!(company: @company, thresholds: { "table_open" => 30 })
    assert_equal 30, alerts.sole.threshold_minutes

    @company.update!(disabled_modules: [ "restaurant" ])
    assert_empty alerts
  end
end
