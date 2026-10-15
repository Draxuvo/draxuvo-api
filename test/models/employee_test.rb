require "test_helper"

class EmployeeTest < ActiveSupport::TestCase
  test "requires a name" do
    employee = Employee.new(company: companies(:one), name: "")
    assert_not employee.valid?
    assert employee.errors[:name].any?
  end

  test "email must have a valid format but may be blank" do
    assert_not Employee.new(company: companies(:one), name: "Ana", email: "no-es-correo").valid?
    assert Employee.new(company: companies(:one), name: "Ana", email: "").valid?
    assert Employee.new(company: companies(:one), name: "Ana", email: nil).valid?
  end

  test "email is unique across the whole system, not per company" do
    duplicate = Employee.new(company: companies(:two), name: "Otra Ana", email: employees(:one).email)
    assert_not duplicate.valid?
    assert duplicate.errors[:email].any?
  end

  test "blank emails do not collide" do
    Employee.create!(company: companies(:one), name: "Sin correo 1", email: "")
    assert Employee.new(company: companies(:two), name: "Sin correo 2", email: "").valid?
  end

  test "status defaults to inactive and exposes the enum" do
    employee = Employee.new
    assert employee.inactive?
    assert_equal({ "active" => 0, "inactive" => 1 }, Employee.statuses)
    assert employees(:one).active?
  end

  test "search matches name, position and department case-insensitively" do
    assert_includes Employee.search("ana tor"), employees(:one)
    assert_includes Employee.search("ADMINISTRADORA"), employees(:one)
    assert_includes Employee.search("oficina"), employees(:one)
    assert_not_includes Employee.search("ana tor"), employees(:two)
  end

  test "search without a term returns everything" do
    assert_equal Employee.count, Employee.search("").count
    assert_equal Employee.count, Employee.search(nil).count
  end

  test "parsed_name_parts with three or more words splits first names, last and second last" do
    assert_equal({ first_name: "Ana", last_name: "Torres", second_last_name: "Ruiz" },
                 employees(:one).parsed_name_parts)
    employee = Employee.new(name: "Juan Carlos López García")
    assert_equal({ first_name: "Juan Carlos", last_name: "López", second_last_name: "García" },
                 employee.parsed_name_parts)
  end

  test "parsed_name_parts with two words repeats the last name as second last name" do
    assert_equal({ first_name: "Luis", last_name: "Ramírez", second_last_name: "Ramírez" },
                 employees(:two).parsed_name_parts)
  end

  test "parsed_name_parts with one word repeats the name in every part" do
    assert_equal({ first_name: "Cher", last_name: "Cher", second_last_name: "Cher" },
                 Employee.new(name: "Cher").parsed_name_parts)
  end

  test "parsed_name_parts ignores extra whitespace" do
    parts = Employee.new(name: "  Ana   Torres  Ruiz ").parsed_name_parts
    assert_equal "Ana", parts[:first_name]
    assert_equal "Ruiz", parts[:second_last_name]
  end

  test "destroying an employee removes attendances and nullifies work orders" do
    employee = employees(:pro_other_employee)
    order = work_orders(:pro_done)
    Attendance.create!(employee: employee, company: employee.company, checkin_at: Time.current)
    assert_difference -> { Attendance.count }, -1 do
      employee.destroy!
    end
    assert_nil order.reload.employee_id
  end
end
