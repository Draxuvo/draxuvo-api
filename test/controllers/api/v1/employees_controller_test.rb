require "test_helper"

# Contrato: specs/036-personal-asistencia-unificados/contracts/people-attendance-api.md
class Api::V1::EmployeesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @admin = create_member(@company, role: :admin)
    @manager = users(:pro_manager)
    @employee = @company.employees.create!(name: "Luis Pérez", position: "Mesero", status: :active)
    ActionMailer::Base.deliveries.clear
  end

  def headers_for(user) = auth_headers(user, @company)

  # --- marcar a otro ---------------------------------------------------------------------------

  test "admin and owner check in and out another employee with the current time" do
    [ @admin, @owner ].each do |boss|
      employee = @company.employees.create!(name: "Persona #{boss.id}", status: :active)
      post "/api/v1/employees/#{employee.id}/checkin", headers: headers_for(boss)
      assert_response :created
      assert_equal boss.id, response.parsed_body.dig("checkin_by", "id")
      assert_equal false, response.parsed_body["checkin_captured"]

      post "/api/v1/employees/#{employee.id}/checkout", headers: headers_for(boss)
      assert_response :ok
      assert_equal boss.id, response.parsed_body.dig("checkout_by", "id")
    end
  end

  test "a boss can capture a past time and it is flagged" do
    post "/api/v1/employees/#{@employee.id}/checkin", params: { at: 3.hours.ago.iso8601 }, headers: headers_for(@admin)
    assert_response :created
    assert response.parsed_body["checkin_captured"]

    post "/api/v1/employees/#{@employee.id}/checkout", params: { at: 1.hour.ago.iso8601 }, headers: headers_for(@admin)
    assert_response :ok
    assert response.parsed_body["checkout_captured"]
    assert_equal 120, response.parsed_body["duration_minutes"]
  end

  test "manager and staff cannot mark another employee" do
    [ @manager, users(:pro_staff) ].each do |user|
      assert_no_difference -> { Attendance.count } do
        post "/api/v1/employees/#{@employee.id}/checkin", headers: headers_for(user)
        assert_response :forbidden
        post "/api/v1/employees/#{@employee.id}/checkout", headers: headers_for(user)
        assert_response :forbidden
      end
    end
  end

  test "an inactive employee cannot be marked in" do
    @employee.update!(status: :inactive)
    post "/api/v1/employees/#{@employee.id}/checkin", headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "employee_inactive", response.parsed_body.dig("error", "details", "code")
  end

  test "marking another company's employee is 404" do
    post "/api/v1/employees/#{employees(:one).id}/checkin", headers: headers_for(@admin)
    assert_response :not_found
  end

  test "future time, double check-in, overlap and missing check-in are 422 without new records" do
    post "/api/v1/employees/#{@employee.id}/checkin", params: { at: 30.minutes.from_now.iso8601 }, headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "future_time", response.parsed_body.dig("error", "code")

    post "/api/v1/employees/#{@employee.id}/checkout", headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "no_open_attendance", response.parsed_body.dig("error", "code")

    post "/api/v1/employees/#{@employee.id}/checkin", headers: headers_for(@admin)
    assert_response :created
    assert_no_difference -> { @employee.attendances.count } do
      post "/api/v1/employees/#{@employee.id}/checkin", headers: headers_for(@admin)
    end
    assert_response :unprocessable_entity
    assert_equal "already_open", response.parsed_body.dig("error", "code")

    post "/api/v1/employees/#{@employee.id}/checkout", params: { at: 5.hours.ago.iso8601 }, headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "before_checkin", response.parsed_body.dig("error", "code")
  end

  test "an unreadable time is 422 invalid_time" do
    post "/api/v1/employees/#{@employee.id}/checkin", params: { at: "ayer" }, headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "invalid_time", response.parsed_body.dig("error", "details", "code")
  end

  # --- alta con acceso --------------------------------------------------------------------------

  test "create without status is active and without email creates no user" do
    assert_no_difference -> { User.count } do
      post "/api/v1/employees", params: { employee: { name: "Sin Correo" } }, headers: headers_for(@manager)
    end
    assert_response :created
    assert_equal "active", response.parsed_body["status"]
  end

  test "create with email and role gives access with that role" do
    assert_difference -> { @company.user_companies.count }, 1 do
      post "/api/v1/employees", params: { employee: { name: "Marta Gómez López", email: "marta@acceso.test", phone: "5511112222" }, access: { role: "manager" } },
           headers: headers_for(@admin)
    end
    assert_response :created
    assert_equal "manager", response.parsed_body.dig("access", "role")
    assert_equal "manager", @company.user_companies.find_by(user: User.find_by(email: "marta@acceso.test")).role
  end

  test "access without a role defaults to staff" do
    post "/api/v1/employees", params: { employee: { name: "Pedro Ríos", email: "pedro@acceso.test", phone: "5511112222" }, access: { role: "" } },
         headers: headers_for(@owner)
    assert_response :created
    assert_equal "staff", response.parsed_body.dig("access", "role")
  end

  test "an email without access is only contact data" do
    assert_no_difference -> { User.count } do
      post "/api/v1/employees", params: { employee: { name: "Solo Contacto", email: "contacto@acceso.test", phone: "5511112222" } }, headers: headers_for(@owner)
    end
    assert_response :created
    assert_nil response.parsed_body["access"]
    assert_equal "contacto@acceso.test", response.parsed_body["email"]
  end

  test "asking for access without an email is 422 email_required" do
    post "/api/v1/employees", params: { employee: { name: "Sin Correo" }, access: { role: "staff" } }, headers: headers_for(@owner)
    assert_response :unprocessable_entity
    assert_equal "email_required", response.parsed_body.dig("error", "details", "code")
    assert_nil Employee.find_by(name: "Sin Correo")
  end

  test "a role above the actor's is forbidden" do
    post "/api/v1/employees", params: { employee: { name: "Jefe Nuevo", email: "jefe@acceso.test", phone: "5511112222" }, access: { role: "owner" } },
         headers: headers_for(@admin)
    assert_response :forbidden
    assert_equal "role_not_allowed", response.parsed_body.dig("error", "details", "code")
    assert_nil User.find_by(email: "jefe@acceso.test")
  end

  test "a manager cannot give access, but can register an employee with a contact email" do
    post "/api/v1/employees", params: { employee: { name: "Otro", email: "otro@acceso.test" }, access: { role: "staff" } }, headers: headers_for(@manager)
    assert_response :forbidden

    assert_no_difference -> { User.count } do
      post "/api/v1/employees", params: { employee: { name: "Otro", email: "otro@acceso.test" } }, headers: headers_for(@manager)
    end
    assert_response :created
    assert_nil response.parsed_body["access"]
    assert_equal "otro@acceso.test", response.parsed_body["email"]
  end

  # --- acceso desde la ficha ---------------------------------------------------------------------

  test "grant, change and revoke access keep the employee and their attendance" do
    post "/api/v1/employees/#{@employee.id}/access", params: { email: "luis@acceso.test", phone: "5511112222", role: "staff" }, headers: headers_for(@admin)
    assert_response :created
    assert_equal "staff", response.parsed_body.dig("access", "role")

    post "/api/v1/employees/#{@employee.id}/checkin", headers: headers_for(@admin)
    patch "/api/v1/employees/#{@employee.id}/access", params: { role: "manager" }, headers: headers_for(@admin)
    assert_response :ok
    assert_equal "manager", response.parsed_body.dig("access", "role")

    assert_no_difference -> { Employee.count + Attendance.count } do
      delete "/api/v1/employees/#{@employee.id}/access", headers: headers_for(@admin)
    end
    assert_response :ok
    assert_nil response.parsed_body["access"]
    assert_nil @employee.reload.user_id
  end

  test "granting access to someone already in the company is 422 already_member" do
    post "/api/v1/employees/#{@employee.id}/access", params: { email: @manager.email }, headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "already_member", response.parsed_body.dig("error", "details", "code")
  end

  test "the last owner cannot be demoted or revoked, but another owner can" do
    owner_employee = @company.employees.create!(name: "Dueño", status: :active, user: @owner)
    patch "/api/v1/employees/#{owner_employee.id}/access", params: { role: "admin" }, headers: headers_for(@owner)
    assert_response :unprocessable_entity
    assert_equal "last_owner", response.parsed_body.dig("error", "details", "code")

    delete "/api/v1/employees/#{owner_employee.id}/access", headers: headers_for(@owner)
    assert_response :unprocessable_entity

    create_member(@company, role: :owner)
    patch "/api/v1/employees/#{owner_employee.id}/access", params: { role: "admin" }, headers: headers_for(@owner)
    assert_response :ok
  end

  test "an admin cannot touch an owner" do
    owner_employee = @company.employees.create!(name: "Dueño", status: :active, user: @owner)
    patch "/api/v1/employees/#{owner_employee.id}/access", params: { role: "staff" }, headers: headers_for(@admin)
    assert_response :forbidden
  end

  test "changing access of an employee without it is 422 no_user" do
    patch "/api/v1/employees/#{@employee.id}/access", params: { role: "staff" }, headers: headers_for(@admin)
    assert_response :unprocessable_entity
    assert_equal "no_user", response.parsed_body.dig("error", "details", "code")
  end

  test "manager and staff cannot manage access" do
    patch "/api/v1/employees/#{@employee.id}/access", params: { role: "staff" }, headers: headers_for(@manager)
    assert_response :forbidden
  end

  # --- lista ----------------------------------------------------------------------------------

  test "index filters by access and only bosses see the access data" do
    granted = @company.employees.find_by!(user: create_member(@company, role: :staff))

    get "/api/v1/employees", params: { access: "with" }, headers: headers_for(@admin)
    ids = response.parsed_body["results"].map { |e| e["id"] }
    assert_includes ids, granted.id
    assert_not_includes ids, @employee.id
    assert response.parsed_body["results"].first.key?("access")

    get "/api/v1/employees", params: { access: "without" }, headers: headers_for(@admin)
    assert_not_includes response.parsed_body["results"].map { |e| e["id"] }, granted.id

    get "/api/v1/employees", headers: headers_for(@manager)
    assert_response :ok
    assert response.parsed_body["results"].none? { |e| e.key?("access") }
  end

  # --- baja --------------------------------------------------------------------------------------

  test "deactivating an employee suspends their access and reactivating restores it" do
    user = create_member(@company, role: :staff)
    employee = @company.employees.find_by!(user: user)

    get "/api/v1/employees", headers: headers_for(user)
    assert_response :ok

    patch "/api/v1/employees/#{employee.id}/active", headers: headers_for(@admin)
    assert_equal "inactive", response.parsed_body["status"]

    get "/api/v1/employees", headers: headers_for(user)
    assert_response :forbidden
    assert_equal "employee_inactive", response.parsed_body.dig("error", "details", "code")

    patch "/api/v1/employees/#{employee.id}/active", headers: headers_for(@admin)
    get "/api/v1/employees", headers: headers_for(user)
    assert_response :ok
    assert_equal "staff", @company.user_companies.find_by(user: user).role
  end

  test "an inactive employee in one company does not block the same user in another" do
    user = create_member(@company, role: :manager)
    @company.employees.create!(name: "Baja", status: :inactive, user: user)
    other = companies(:one)
    create_member(other, role: :staff, user: user)

    get "/api/v1/employees", headers: auth_headers(user, other)
    assert_response :ok
  end

  test "the super admin is never blocked" do
    @company.employees.create!(name: "Super", status: :inactive, user: users(:super_admin))
    get "/api/v1/employees", headers: headers_for(users(:super_admin))
    assert_response :ok
  end

  # --- quien dirige no es personal ---------------------------------------------------------------

  test "owners, admins and managers are not in the employee list nor reachable as employees" do
    staff = @company.employees.find_by!(user: create_member(@company, role: :staff))
    boss_card = @company.employees.create!(name: "Jefa con ficha", status: :active, user: @admin)

    get "/api/v1/employees", params: { page_size: 100 }, headers: headers_for(@owner)
    ids = response.parsed_body["results"].map { |e| e["id"] }
    assert_includes ids, staff.id
    assert_includes ids, @employee.id, "un empleado sin acceso sigue siendo equipo"
    assert_not_includes ids, boss_card.id

    get "/api/v1/employees/#{boss_card.id}", headers: headers_for(@owner)
    assert_response :not_found
    post "/api/v1/employees/#{boss_card.id}/checkin", headers: headers_for(@owner)
    assert_response :not_found
  end

  test "promoting an employee to manager takes them out of the team but keeps the card" do
    staff_user = create_member(@company, role: :staff)
    card = @company.employees.find_by!(user: staff_user)

    patch "/api/v1/employees/#{card.id}/access", params: { role: "manager" }, headers: headers_for(@owner)
    assert_response :ok

    get "/api/v1/employees", params: { page_size: 100 }, headers: headers_for(@owner)
    assert_not_includes response.parsed_body["results"].map { |e| e["id"] }, card.id
    assert Employee.exists?(card.id)
  end
end
