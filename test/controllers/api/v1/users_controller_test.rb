require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/users", solo super admin). FR-019, SC-007.
class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/users".freeze

  setup do
    @pro_admin = create_member(companies(:pro_co), role: :admin)
  end

  test "staff, manager, admin and owner get 403 on every /users action" do
    target = users(:one_owner)
    actors = { staff: users(:pro_staff), manager: users(:pro_manager), admin: @pro_admin, owner: users(:pro_co_owner) }

    actors.each do |name, actor|
      headers = auth_headers(actor, companies(:pro_co))

      get BASE, headers: headers
      assert_response :forbidden, "#{name} index"

      get "#{BASE}/#{target.id}", headers: headers
      assert_response :forbidden, "#{name} show"

      post BASE, params: { user: { first_name: "X", last_name: "Y", email: "x-#{name}@y.test", phone: "1", role: "super_admin" } },
                 headers: headers, as: :json
      assert_response :forbidden, "#{name} create"

      patch "#{BASE}/#{target.id}", params: { user: { first_name: "Hacked" } }, headers: headers, as: :json
      assert_response :forbidden, "#{name} update"

      patch "#{BASE}/#{target.id}/update_active", headers: headers
      assert_response :forbidden, "#{name} update_active"

      patch "#{BASE}/#{target.id}/active", headers: headers
      assert_response :forbidden, "#{name} active"

      delete "#{BASE}/#{target.id}", headers: headers
      assert_response :forbidden, "#{name} destroy"
    end

    target.reload
    assert_equal "Dueño", target.first_name
    assert target.active?
    assert User.exists?(target.id)
    assert_not User.exists?(email: "x-owner@y.test")
  end

  test "an owner cannot make itself super admin through /users" do
    owner = users(:pro_co_owner)

    patch "#{BASE}/#{owner.id}", params: { user: { role: "super_admin", company_ids: [ companies(:one).id ] } },
                                 headers: auth_headers(owner), as: :json

    assert_response :forbidden
    assert_not owner.reload.super_admin?
    assert_not_includes owner.companies.reload, companies(:one)
  end

  test "the super admin lists, reads and updates any user" do
    headers = auth_headers(users(:super_admin), companies(:pro_co))

    get BASE, headers: headers
    assert_response :ok
    assert json["results"].any?

    get "#{BASE}/#{users(:one_owner).id}", headers: headers
    assert_response :ok

    patch "#{BASE}/#{users(:one_owner).id}", params: { user: { first_name: "Renombrado" } }, headers: headers, as: :json
    assert_response :ok
    assert_equal "Renombrado", users(:one_owner).reload.first_name
  end

  private

  def json
    JSON.parse(response.body)
  end
end
