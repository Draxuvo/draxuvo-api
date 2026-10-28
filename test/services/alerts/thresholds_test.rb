require "test_helper"

class Alerts::ThresholdsTest < ActiveSupport::TestCase
  test "without a saved setting the defaults apply" do
    thresholds = Alerts::Thresholds.new(companies(:resto_co))
    assert_equal 10, thresholds.minutes("kitchen_wait", "kitchen")
    assert_equal 5, thresholds.minutes("kitchen_wait", "bar")
    assert_equal 90, thresholds.minutes("table_open")
  end

  test "a saved setting wins and an unknown station kind uses other" do
    AlertSetting.create!(company: companies(:resto_co), thresholds: { "kitchen_wait" => { "other" => 3, "bar" => 2 }, "table_open" => 30 })
    thresholds = Alerts::Thresholds.new(companies(:resto_co))
    assert_equal 2, thresholds.minutes("kitchen_wait", "bar")
    assert_equal 3, thresholds.minutes("kitchen_wait", "banquets")
    assert_equal 10, thresholds.minutes("kitchen_wait", "kitchen")
    assert_equal 30, thresholds.minutes("table_open")
  end
end
