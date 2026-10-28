require "test_helper"

class AlertSettingTest < ActiveSupport::TestCase
  def setting(**attrs) = AlertSetting.new(company: companies(:resto_co), **attrs)

  test "without changes every limit comes from the defaults" do
    effective = setting.effective
    assert_equal({ "kitchen" => 10, "bar" => 5, "other" => 10 }, effective["kitchen_wait"])
    assert_equal({ "kitchen" => 25, "bar" => 10, "other" => 25 }, effective["kitchen_preparing"])
    assert_equal 90, effective["table_open"]
    assert_equal 1440, effective["work_order_stalled"]
  end

  test "minutes_for picks the station kind and falls back to other" do
    s = setting
    assert_equal 5, s.minutes_for("kitchen_wait", "bar")
    assert_equal 25, s.minutes_for("kitchen_preparing", "kitchen")
    assert_equal 10, s.minutes_for("kitchen_wait", "banquets")
    assert_equal 10, s.minutes_for("kitchen_wait", nil)
    assert_equal 90, s.minutes_for("table_open")
  end

  test "stored values win over the defaults and the rest keeps its default" do
    s = setting(thresholds: { "kitchen_wait" => { "bar" => 2 }, "table_open" => 30 })
    assert s.valid?
    assert_equal 2, s.minutes_for("kitchen_wait", "bar")
    assert_equal 10, s.minutes_for("kitchen_wait", "kitchen")
    assert_equal 30, s.minutes_for("table_open")
  end

  test "limits must be whole minutes between 1 and 10080" do
    [ 0, -5, 10_081, 1.5, "20", nil ].each do |bad|
      assert_not setting(thresholds: { "table_open" => bad }).valid?, "#{bad.inspect} no debe valer"
    end
    assert setting(thresholds: { "table_open" => 1 }).valid?
    assert setting(thresholds: { "table_open" => 10_080 }).valid?
  end

  test "unknown kinds and unknown station kinds are rejected" do
    assert_not setting(thresholds: { "low_stock" => 5 }).valid?
    assert_not setting(thresholds: { "kitchen_wait" => { "banquets" => 5 } }).valid?
    assert_not setting(thresholds: { "kitchen_wait" => 5 }).valid?
  end

  test "summary hour is 0 to 23 and the time zone must exist" do
    assert_not setting(summary_hour: 24).valid?
    assert_not setting(summary_hour: -1).valid?
    assert_not setting(time_zone: "Mars/Olympus").valid?
    assert setting(summary_hour: 0, time_zone: "America/Tijuana").valid?
  end

  test "merge_thresholds changes only what it is given" do
    s = setting(thresholds: { "kitchen_wait" => { "bar" => 2 }, "table_open" => 30 })
    s.merge_thresholds("kitchen_wait" => { "kitchen" => 15 }, "work_order_stalled" => 60)
    assert_equal({ "kitchen_wait" => { "bar" => 2, "kitchen" => 15 }, "table_open" => 30, "work_order_stalled" => 60 }, s.thresholds)
  end

  test "for returns an unsaved default setting when the company never configured one" do
    found = AlertSetting.for(companies(:resto_co))
    assert found.new_record?
    assert_equal 8, found.summary_hour
  end
end
