require "test_helper"

class Reports::ComparisonTest < ActiveSupport::TestCase
  def range(from, to)
    Date.parse(from).beginning_of_day..Date.parse(to).end_of_day
  end

  test "the previous range has the same number of days and ends the day before" do
    previous = Reports::Comparison.previous_range(range("2026-10-01", "2026-10-21"))

    assert_equal Date.new(2026, 9, 10), previous.first.to_date
    assert_equal Date.new(2026, 9, 30), previous.last.to_date
  end

  test "a month of 31 days compares against the 31 days before" do
    previous = Reports::Comparison.previous_range(range("2026-03-01", "2026-03-31"))

    assert_equal Date.new(2026, 1, 29), previous.first.to_date
    assert_equal Date.new(2026, 2, 28), previous.last.to_date
  end

  test "a single day compares against the day before" do
    previous = Reports::Comparison.previous_range(range("2026-10-21", "2026-10-21"))

    assert_equal Date.new(2026, 10, 20), previous.first.to_date
    assert_equal Date.new(2026, 10, 20), previous.last.to_date
  end

  test "the range covers whole days" do
    previous = Reports::Comparison.previous_range(range("2026-10-08", "2026-10-14"))

    assert_equal previous.first, previous.first.beginning_of_day
    assert_equal previous.last.to_i, previous.last.end_of_day.to_i
  end
end
