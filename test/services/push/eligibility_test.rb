require "test_helper"

class Push::EligibilityTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @waiter = users(:resto_waiter)
  end

  test "a real company with access and the module is ok" do
    assert Push::Eligibility.company_ok?(@company, "check_ready")
  end

  test "demo companies, companies without access, a module that is off or PUSH_ENABLED=false never send" do
    @company.update_columns(demo: true)
    assert_not Push::Eligibility.company_ok?(@company, "check_ready")
    @company.update_columns(demo: false)

    assert_not Push::Eligibility.company_ok?(companies(:expired_co), "low_stock")
    assert_not Push::Eligibility.company_ok?(companies(:basic_co), "check_ready")
    with_env("PUSH_ENABLED" => "false") { assert_not Push::Eligibility.company_ok?(@company, "check_ready") }
  end

  test "recipient status follows membership, role, employee status, preference and devices" do
    assert_equal :no_devices, Push::Eligibility.recipient_status(@waiter, @company, "check_ready")

    register_device(@waiter)
    assert_equal :ok, Push::Eligibility.recipient_status(@waiter, @company, "check_ready")
    assert_equal :ineligible, Push::Eligibility.recipient_status(@waiter, @company, "operational_alert"), "el staff no recibe alertas"
    assert_equal :ineligible, Push::Eligibility.recipient_status(@waiter, companies(:pro_co), "check_ready"), "no es miembro"

    NotificationPreference.for(@waiter, @company).update!(push_check_ready: false)
    assert_equal :skipped_preference, Push::Eligibility.recipient_status(@waiter, @company, "check_ready")
  end

  test "an inactive account or a deactivated employee is not eligible" do
    register_device(@waiter)
    employee = @company.employees.find_by(user_id: @waiter.id) ||
               @company.employees.create!(name: "Mesero Resto", user: @waiter, status: :active)
    employee.update!(status: :inactive)
    assert_equal :ineligible, Push::Eligibility.recipient_status(@waiter, @company, "check_ready")

    employee.update!(status: :active)
    @waiter.update_columns(active: false)
    assert_equal :ineligible, Push::Eligibility.recipient_status(@waiter, @company, "check_ready")
  end
end
