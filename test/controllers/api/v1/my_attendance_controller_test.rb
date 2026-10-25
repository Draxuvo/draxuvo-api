require "test_helper"

# Contrato: specs/026-asistencia-entrada-salida/contracts/attendance-api.md
class Api::V1::MyAttendanceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @staff = users(:pro_staff)
    @employee = employees(:pro_staff_employee)
    @employee.attendances.destroy_all
    @headers = auth_headers(@staff, @company)
  end

  test "today without attendance is none" do
    get "/api/v1/my_attendance/today", headers: @headers

    assert_response :ok
    body = response.parsed_body
    assert body["eligible"]
    assert_equal "none", body["state"]
    assert_nil body["current"]
  end

  test "check_in creates a normal open attendance and is idempotent" do
    assert_difference -> { @employee.attendances.count }, 1 do
      post "/api/v1/my_attendance/check_in", headers: @headers
      assert_response :created
      post "/api/v1/my_attendance/check_in", headers: @headers
      assert_response :ok
    end

    body = response.parsed_body
    assert_equal "working", body["state"]
    assert body["current"]["open"]
    assert_equal "normal", Attendance.where(employee: @employee).last.attendance_type
  end

  test "check_out closes the open attendance and reports done with duration" do
    @employee.attendances.create!(company: @company, checkin_at: 90.minutes.ago)

    post "/api/v1/my_attendance/check_out", headers: @headers

    assert_response :ok
    body = response.parsed_body
    assert_equal "done", body["state"]
    assert_equal 90, body["last"]["duration_minutes"]
    assert_not body["last"]["open"]
  end

  test "check_out without an open attendance is 422" do
    post "/api/v1/my_attendance/check_out", headers: @headers

    assert_response :unprocessable_entity
    assert_equal "no_open_attendance", response.parsed_body.dig("error", "code")
  end

  test "an entry without checkout from a previous day is not a shift in progress" do
    old = @employee.attendances.create!(company: @company, checkin_at: 2.days.ago)

    get "/api/v1/my_attendance/today", headers: @headers
    assert_equal "none", response.parsed_body["state"]

    post "/api/v1/my_attendance/check_out", headers: @headers
    assert_response :unprocessable_entity

    post "/api/v1/my_attendance/check_in", headers: @headers
    assert_response :created
    post "/api/v1/my_attendance/check_out", headers: @headers
    assert_response :ok
    assert_nil old.reload.checkout_at
  end

  test "a user without employee is not eligible" do
    owner = users(:pro_co_owner)

    get "/api/v1/my_attendance/today", headers: auth_headers(owner, @company)
    assert_response :ok
    assert_equal false, response.parsed_body["eligible"]

    post "/api/v1/my_attendance/check_in", headers: auth_headers(owner, @company)
    assert_response :unprocessable_entity
    assert_equal "not_eligible", response.parsed_body.dig("error", "code")
  end

  test "requires a session" do
    get "/api/v1/my_attendance/today"
    assert_response :unauthorized
  end

  test "login no longer creates an attendance" do
    @staff.update!(password: "Demo12345*")

    assert_no_difference -> { Attendance.count } do
      post "/api/v1/auth/login", params: { email: @staff.email, password: "Demo12345*" }
    end
    assert_response :ok
  end

  test "does not touch another employee's attendance" do
    other = employees(:pro_other_employee)
    other.attendances.create!(company: @company, checkin_at: 1.hour.ago)

    post "/api/v1/my_attendance/check_out", headers: @headers

    assert_response :unprocessable_entity
    assert_nil other.attendances.last.checkout_at
  end

  test "owners and admins do not mark their own attendance" do
    %i[owner admin].each do |role|
      boss = create_member(@company, role: role)
      @company.employees.create!(name: "Ficha #{role}", status: :active, user: boss)
      headers = auth_headers(boss, @company)

      get "/api/v1/my_attendance/today", headers: headers
      assert_equal false, response.parsed_body["eligible"], role

      assert_no_difference -> { Attendance.count } do
        post "/api/v1/my_attendance/check_in", headers: headers
      end
      assert_response :unprocessable_entity
      assert_equal "not_eligible", response.parsed_body.dig("error", "code")
    end
  end
end
