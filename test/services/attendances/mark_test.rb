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

  # --- Spec 036: marca de otro con hora capturada ---

  def boss_mark
    Attendances::Mark.new(@employee, actor: users(:pro_manager))
  end

  test "the actor is saved and own marks are not captured" do
    Attendances::Mark.new(@employee, actor: users(:pro_staff)).check_in
    attendance = @employee.attendances.last
    assert_equal users(:pro_staff), attendance.checkin_by
    assert_not attendance.checkin_captured
  end

  test "a past check_in is captured by the actor" do
    at = 2.hours.ago
    assert boss_mark.check_in(at: at, strict: true)
    attendance = @employee.attendances.last
    assert_in_delta at.to_f, attendance.checkin_at.to_f, 1
    assert attendance.checkin_captured
    assert_equal users(:pro_manager), attendance.checkin_by
  end

  test "future times are rejected" do
    assert_raises(Attendances::Mark::FutureTime) { boss_mark.check_in(at: 10.minutes.from_now, strict: true) }
    assert_equal 0, @employee.attendances.count
  end

  test "strict check_in with an open shift raises and creates nothing" do
    boss_mark.check_in(at: 3.hours.ago, strict: true)
    assert_raises(Attendances::Mark::AlreadyOpen) { boss_mark.check_in(strict: true) }
    assert_equal 1, @employee.attendances.count
  end

  test "strict check_out records who and when, and rejects a time before the check-in" do
    boss_mark.check_in(at: 3.hours.ago, strict: true)
    assert_raises(Attendances::Mark::BeforeCheckin) { boss_mark.check_out(at: 4.hours.ago, strict: true) }

    attendance = boss_mark.check_out(at: 1.hour.ago, strict: true)
    assert_equal 120, attendance.duration_minutes
    assert attendance.checkout_captured
    assert_equal users(:pro_manager), attendance.checkout_by
    assert attendance.checkout_recorded_at
  end

  test "strict check_out without an open shift raises" do
    assert_raises(Attendances::Mark::NoOpenAttendance) { boss_mark.check_out(at: 1.hour.ago, strict: true) }
  end

  test "overlapping shifts are rejected" do
    @employee.attendances.create!(company: @employee.company, checkin_at: 5.hours.ago, checkout_at: 2.hours.ago)
    assert_raises(Attendances::Mark::Overlap) { boss_mark.check_in(at: 3.hours.ago, strict: true) }
    assert boss_mark.check_in(at: 1.hour.ago, strict: true)
  end

  test "a shift can cross midnight" do
    travel_to Time.zone.local(2026, 10, 20, 9, 0) do
      @employee.attendances.create!(company: @employee.company, checkin_at: Time.zone.local(2026, 10, 19, 22, 0))
      attendance = boss_mark.check_out(at: Time.zone.local(2026, 10, 20, 0, 10), strict: true)
      assert_equal 130, attendance.duration_minutes
    end
  end
end
