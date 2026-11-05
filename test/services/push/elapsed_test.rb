require "test_helper"

class Push::ElapsedTest < ActiveSupport::TestCase
  test "formats like the Alerts screen" do
    {
      0 => "0 min", 45 => "45 min", 59.6 => "1 h", 120 => "2 h", 190 => "3 h 10 min",
      1440 => "1 d", 21_652 => "15 d", (2 * 1440) + (4 * 60) + 5 => "2 d 4 h", -3 => "0 min"
    }.each do |minutes, expected|
      assert_equal expected, Push::Elapsed.format(minutes, locale: "es"), "#{minutes} min"
    end
    assert_equal "3 h 10 min", Push::Elapsed.format(190, locale: "en")
  end
end
