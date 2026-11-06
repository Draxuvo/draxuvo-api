require "test_helper"

# Spec 058 (US2): «Cobro solo por jefes» lo cambia solo el super admin, con bitácora. contracts/api.md.
class Api::V1::CompanyChargePoliciesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/company/charge_policy".freeze

  setup do
    @company = companies(:pos_co)
    @super_admin = users(:super_admin)
  end

  def json = response.parsed_body

  def as_super_admin(company = @company) = auth_headers(@super_admin, company)

  def toggle(enabled, headers = as_super_admin)
    patch PATH, params: { boss_only_charge: enabled }, headers: headers, as: :json
  end

  test "the super admin reads the option, off by default" do
    get PATH, headers: as_super_admin
    assert_response :ok
    assert_equal false, json["boss_only_charge"]
    assert_equal [], json["changes"]
  end

  test "the super admin turns it on and the change is recorded" do
    assert_difference -> { @company.charge_policy_changes.count }, 1 do
      toggle(true)
    end
    assert_response :ok
    assert_equal true, json["boss_only_charge"]
    assert @company.reload.boss_only_charge
    change = json["changes"].first
    assert_equal true, change["enabled"]
    assert_equal @super_admin.full_name, change["actor"]
    assert change["created_at"].present?
  end

  test "saving the same value leaves no record" do
    assert_no_difference -> { ChargePolicyChange.count } do
      toggle(false)
    end
    assert_response :ok
  end

  test "changes come newest first and at most ten" do
    12.times { |i| toggle(i.even?) }
    get PATH, headers: as_super_admin
    assert_equal 10, json["changes"].size
    assert_equal false, json["changes"].first["enabled"]
  end

  test "without the key answers 400" do
    patch PATH, params: {}, headers: as_super_admin, as: :json
    assert_response :bad_request
  end

  test "owner, admin and staff cannot read nor change it" do
    %i[pos_owner pos_admin pos_staff].each do |name|
      headers = auth_headers(users(name), @company)
      toggle(true, headers)
      assert_response :forbidden, name
      get PATH, headers: headers
      assert_response :forbidden, name
    end
    assert_not @company.reload.boss_only_charge
  end

  test "turning it off frees the sales sent to charge and the requested checks of that company only" do
    @company.update!(boss_only_charge: true)
    sale = open_sale(users(:pos_staff), [ products(:pos_cuaderno), 1 ])
    sale.update_columns(submitted_at: Time.current)

    resto = companies(:resto_co)
    resto.update!(boss_only_charge: true)
    check = checks(:open_check)
    check.update_columns(charge_requested_at: Time.current, charge_requested_by_id: users(:resto_waiter).id)

    other = open_sale(users(:pos_staff2), [ products(:pos_cuaderno), 1 ])
    other.update_columns(submitted_at: Time.current)

    toggle(false, as_super_admin(resto))
    assert_response :ok
    assert_nil check.reload.charge_requested_at
    assert_nil check.charge_requested_by_id
    assert_not_nil other.reload.submitted_at, "another company keeps its marks"

    toggle(false)
    assert_nil sale.reload.submitted_at
  end

  test "the subscription shows the option to the owner" do
    @company.update!(boss_only_charge: true)
    get "/api/v1/subscription", headers: auth_headers(users(:pos_owner), @company)
    assert_response :ok
    assert_equal true, json["boss_only_charge"]
  end
end
