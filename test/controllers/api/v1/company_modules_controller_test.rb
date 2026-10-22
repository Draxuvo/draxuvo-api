require "test_helper"

# Contrato: specs/017-modulos-solo-super-admin/contracts/api.md (PATCH /company/modules). Solo el super admin
# cambia los módulos de una empresa; los demás roles reciben 403 (spec 017, FR-004).
class Api::V1::CompanyModulesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/company/modules".freeze

  BASIC_MODULES = %w[employees attendance inventory reports].freeze
  PRO_MODULES = %w[employees attendance inventory work_orders tickets reports restaurant terminals].freeze

  def as_super_admin(company) = auth_headers(users(:super_admin), company)

  test "the super admin disables a module of the plan and gets the module lists back" do
    patch PATH, params: { disabled_modules: [ "inventory" ] }, headers: as_super_admin(companies(:basic_co)), as: :json

    assert_response :ok
    assert_equal %w[employees attendance reports], json["active_modules"]
    assert_equal BASIC_MODULES, json["available_modules"]
    assert_equal %w[inventory], json["disabled_modules"]
    assert_equal %w[inventory], companies(:basic_co).reload.disabled_modules
  end

  test "the list replaces the previous one and an empty list turns everything on" do
    companies(:pro_co).update!(disabled_modules: %w[tickets reports])

    patch PATH, params: { disabled_modules: [] }, headers: as_super_admin(companies(:pro_co)), as: :json

    assert_response :ok
    assert_equal PRO_MODULES, json["active_modules"]
    assert_equal [], json["disabled_modules"]
    assert_equal [], companies(:pro_co).reload.disabled_modules
  end

  test "each module whose state changed leaves one record with its author and new state" do
    company = companies(:pro_co)
    company.update!(disabled_modules: %w[tickets])

    assert_difference -> { company.module_changes.count }, 2 do
      patch PATH, params: { disabled_modules: %w[reports] }, headers: as_super_admin(company), as: :json
    end

    changes = company.module_changes.order(:id).pluck(:module, :enabled, :actor_id).sort
    assert_equal [ [ "reports", false, users(:super_admin).id ], [ "tickets", true, users(:super_admin).id ] ], changes
  end

  test "saving the same list leaves no record" do
    company = companies(:pro_co)
    company.update!(disabled_modules: %w[tickets])

    assert_no_difference -> { ModuleChange.count } do
      patch PATH, params: { disabled_modules: %w[tickets] }, headers: as_super_admin(company), as: :json
    end
    assert_response :ok
  end

  test "disabling a module does not delete its data" do
    company = companies(:basic_co)
    product = company.products.create!(name: "Tuerca", sku: "TUE-1", stock: 4)

    patch PATH, params: { disabled_modules: [ "inventory" ] }, headers: as_super_admin(company), as: :json

    assert_response :ok
    assert Product.exists?(product.id)
  end

  test "rejects a module outside the plan with 422 and leaves no record" do
    assert_no_difference -> { ModuleChange.count } do
      patch PATH, params: { disabled_modules: [ "work_orders" ] }, headers: as_super_admin(companies(:basic_co)), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "work_orders", json.dig("error", "details", "module")
    assert_equal [], companies(:basic_co).reload.disabled_modules
  end

  test "rejects an unknown module with 422" do
    patch PATH, params: { disabled_modules: [ "spaceships" ] }, headers: as_super_admin(companies(:pro_co)), as: :json

    assert_response :unprocessable_entity
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "spaceships", json.dig("error", "details", "module")
  end

  test "a request without the list answers 400" do
    patch PATH, params: {}, headers: as_super_admin(companies(:pro_co)), as: :json
    assert_response :bad_request
  end

  test "owners, admins, managers and staff cannot change modules, by any means" do
    admin = users(:pro_staff)
    admin.user_companies.find_by!(company: companies(:pro_co)).update!(role: :admin)

    [ users(:pro_co_owner), admin, users(:pro_manager) ].each do |user|
      assert_no_difference -> { ModuleChange.count } do
        patch PATH, params: { disabled_modules: [ "tickets" ] }, headers: auth_headers(user, companies(:pro_co)), as: :json
      end
      assert_response :forbidden, "#{user.email} should be forbidden"
    end
    staff = create_member(companies(:pro_co), role: :staff)
    patch PATH, params: { disabled_modules: [ "tickets" ] }, headers: auth_headers(staff, companies(:pro_co)), as: :json
    assert_response :forbidden
    assert_equal [], companies(:pro_co).reload.disabled_modules
  end

  test "a branch follows the modules of its parent: changing the branch does not touch the parent" do
    parent = companies(:enterprise_co)
    branch = Company.create!(name: "Sucursal", parent: parent)

    patch PATH, params: { disabled_modules: [ "reports" ] }, headers: as_super_admin(branch), as: :json

    assert_response :ok
    assert_equal %w[reports], branch.reload.disabled_modules
    assert_equal [], parent.reload.disabled_modules
    assert_not_includes json["active_modules"], "reports"
  end

  private

  def json
    JSON.parse(response.body)
  end

  # --- spec 030: Terminales es un módulo de Pro y Empresa ---

  test "the super admin turns Terminales off and on again and each change is recorded" do
    company = companies(:pro_co)

    assert_difference -> { company.module_changes.where(module: "terminals").count }, 2 do
      patch PATH, params: { disabled_modules: %w[terminals] }, headers: as_super_admin(company), as: :json
      assert_response :ok
      assert_not_includes response.parsed_body["active_modules"], "terminals"
      patch PATH, params: { disabled_modules: [] }, headers: as_super_admin(company), as: :json
      assert_includes response.parsed_body["active_modules"], "terminals"
    end
  end

  test "Terminales is not active in a basic company even with an empty disabled list" do
    company = companies(:basic_co)

    patch PATH, params: { disabled_modules: [] }, headers: as_super_admin(company), as: :json

    assert_response :ok
    assert_equal BASIC_MODULES, response.parsed_body["active_modules"]
    assert_not_includes response.parsed_body["active_modules"], "terminals"
  end
end
