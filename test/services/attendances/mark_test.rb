require "test_helper"

class Attendances::MarkTest < ActiveSupport::TestCase
  setup do
    @employee = employees(:pro_staff_employee)
    @employee.attendances.destroy_all
    @mark = Attendances::Mark.new(@employee)
  end

  test "state goes none, working, done" do
    assert_equal "none", @mark.state[:state]
    assert @mark.check_in
    assert_equal "working", @mark.state[:state]
    @mark.check_out
    assert_equal "done", @mark.state[:state]
  end

  test "check_in twice creates one attendance" do
    assert @mark.check_in
    assert_not @mark.check_in
    assert_equal 1, @employee.attendances.count
  end

  test "a second shift can start after checking out" do
    @mark.check_in
    @mark.check_out
    assert @mark.check_in
    assert_equal 2, @employee.attendances.count
  end

  test "check_out without open attendance raises" do
    assert_raises(Attendances::Mark::NoOpenAttendance) { @mark.check_out }
  end
end
