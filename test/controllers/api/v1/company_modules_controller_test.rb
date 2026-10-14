require "test_helper"

# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (PATCH /company/modules, FR-027).
class Api::V1::CompanyModulesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/company/modules".freeze

  BASIC_MODULES = %w[employees attendance inventory].freeze
  PRO_MODULES = %w[employees attendance inventory work_orders tickets reports].freeze

  test "an owner disables a module of the plan and gets the module lists back" do
    patch PATH, params: { disabled_modules: [ "inventory" ] },
                headers: auth_headers(users(:basic_co_owner)), as: :json

    assert_response :ok
    assert_equal %w[employees attendance], json["active_modules"]
    assert_equal BASIC_MODULES, json["available_modules"]
    assert_equal %w[inventory], json["disabled_modules"]
    assert_equal %w[inventory], companies(:basic_co).reload.disabled_modules
  end

  test "the list replaces the previous one and an empty list turns everything on" do
    companies(:pro_co).update!(disabled_modules: %w[tickets reports])

    patch PATH, params: { disabled_modules: [] }, headers: auth_headers(users(:pro_co_owner)), as: :json

    assert_response :ok
    assert_equal PRO_MODULES, json["active_modules"]
    assert_equal [], json["disabled_modules"]
    assert_equal [], companies(:pro_co).reload.disabled_modules
  end

  test "disabling a module does not delete its data" do
    company = companies(:basic_co)
    product = company.products.create!(name: "Tuerca", sku: "TUE-1", stock: 4)

    patch PATH, params: { disabled_modules: [ "inventory" ] },
                headers: auth_headers(users(:basic_co_owner)), as: :json

    assert_response :ok
    assert Product.exists?(product.id)
  end

  test "rejects a module outside the plan with 422" do
    patch PATH, params: { disabled_modules: [ "reports" ] },
                headers: auth_headers(users(:basic_co_owner)), as: :json

    assert_response :unprocessable_entity
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "reports", json.dig("error", "details", "module")
    assert_equal [], companies(:basic_co).reload.disabled_modules
  end

  test "rejects an unknown module with 422" do
    patch PATH, params: { disabled_modules: [ "spaceships" ] },
                headers: auth_headers(users(:pro_co_owner)), as: :json

    assert_response :unprocessable_entity
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "spaceships", json.dig("error", "details", "module")
  end

  test "staff and managers cannot change modules" do
    %i[pro_staff pro_manager].each do |user|
      patch PATH, params: { disabled_modules: [ "tickets" ] },
                  headers: auth_headers(users(user), companies(:pro_co)), as: :json

      assert_response :forbidden, "#{user} should be forbidden"
    end
    assert_equal [], companies(:pro_co).reload.disabled_modules
  end

  test "an admin can change modules" do
    admin = users(:pro_staff)
    admin.update!(role: :admin)

    patch PATH, params: { disabled_modules: [ "tickets" ] },
                headers: auth_headers(admin, companies(:pro_co)), as: :json

    assert_response :ok
    assert_not_includes json["active_modules"], "tickets"
  end

  test "the super admin can change modules of any company" do
    patch PATH, params: { disabled_modules: [ "reports" ] },
                headers: auth_headers(users(:super_admin), companies(:pro_co)), as: :json

    assert_response :ok
    assert_equal %w[reports], companies(:pro_co).reload.disabled_modules
  end

  private

  def json
    JSON.parse(response.body)
  end
end
