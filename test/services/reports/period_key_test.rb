require "test_helper"

class Reports::PeriodKeyTest < ActiveSupport::TestCase
  TIME = Time.utc(2026, 3, 9, 15, 30)

  test "groups by day, ISO week, month and year" do
    assert_equal "2026-03-09", Reports::PeriodKey.call(TIME, "day")
    assert_equal "2026-W11", Reports::PeriodKey.call(TIME, "week")
    assert_equal "2026-03", Reports::PeriodKey.call(TIME, "month")
    assert_equal "2026", Reports::PeriodKey.call(TIME, "year")
  end

  test "an unknown grouping falls back to month" do
    assert_equal "2026-03", Reports::PeriodKey.call(TIME, "decade")
  end

  test "the ISO week of the first days of January belongs to the ISO year" do
    assert_equal "2026-W01", Reports::PeriodKey.call(Time.utc(2025, 12, 29, 12), "week")
    assert_equal "2020-W53", Reports::PeriodKey.call(Time.utc(2021, 1, 3, 12), "week")
  end
end
