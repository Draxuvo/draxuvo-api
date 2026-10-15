require "test_helper"

class AttendanceTest < ActiveSupport::TestCase
  test "requires a check-in time" do
    attendance = Attendance.new(employee: employees(:one), company: companies(:one))
    assert_not attendance.valid?
    assert attendance.errors[:checkin_at].any?
  end

  test "attendance type defaults to normal" do
    attendance = Attendance.create!(employee: employees(:one), company: companies(:one), checkin_at: Time.current)
    assert attendance.normal?
  end

  test "requires employee and company" do
    attendance = Attendance.new(checkin_at: Time.current)
    assert_not attendance.valid?
    assert attendance.errors[:employee].any?
    assert attendance.errors[:company].any?
  end

  test "enum exposes normal, late and absent" do
    assert_equal({ "normal" => 0, "late" => 1, "absent" => 2 }, Attendance.attendance_types)
    assert attendances(:two).late?
  end

  test "fixtures check out after they check in" do
    [ attendances(:one), attendances(:two) ].each do |attendance|
      assert_operator attendance.checkout_at, :>, attendance.checkin_at
    end
  end

  test "search matches the employee name" do
    assert_includes Attendance.search("torres"), attendances(:one)
    assert_not_includes Attendance.search("torres"), attendances(:two)
    assert_equal Attendance.count, Attendance.search("").count
  end
end
