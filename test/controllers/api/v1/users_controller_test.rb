require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/users", solo super admin). FR-019, SC-007.
class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/users".freeze

  setup do
    @pro_admin = create_member(companies(:pro_co), role: :admin)
  end

  test "staff, admin and owner get 403 on every /users action" do
    target = users(:one_owner)
    actors = { staff: users(:pro_staff), admin: @pro_admin, owner: users(:pro_co_owner) }

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

    patch "#{BASE}/#{owner.id}", params: { user: { role: "super_admin", memberships: [ { company_id: companies(:one).id, role: "owner" } ] } },
                                 headers: auth_headers(owner), as: :json

    assert_response :forbidden
    assert_not owner.reload.super_admin?
    assert_not_includes owner.companies.reload, companies(:one)
  end

  test "the list shows owners and admins even though every member has an employee card (spec 036)" do
    owner = create_member(companies(:pro_co), role: :owner)
    admin = create_member(companies(:pro_co), role: :admin)
    staff = create_member(companies(:pro_co), role: :staff)

    get BASE, params: { page_size: 100 }, headers: auth_headers(users(:super_admin), companies(:pro_co))

    ids = json["results"].map { |u| u["id"] }
    assert_includes ids, owner.id
    assert_includes ids, admin.id
    assert_not_includes ids, staff.id
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

  # Spec 014: el rol se guarda en la membresía de cada empresa (contracts/api.md).
  test "the super admin sets the role of a person in a company" do
    target = users(:pro_staff)

    patch "#{BASE}/#{target.id}", params: { user: { memberships: [ { company_id: companies(:pro_co).id, role: "owner" } ] } },
                                  headers: super_admin_headers, as: :json

    assert_response :ok
    assert_equal "owner", target.role_in(companies(:pro_co))
    assert_equal [ { "id" => companies(:pro_co).id, "role" => "owner" } ],
                 json["companies"].map { |c| c.slice("id", "role") }
  end

  test "changing the role in one company keeps the role in another" do
    target = users(:pro_staff)
    create_member(companies(:two), role: :admin, user: target)

    patch "#{BASE}/#{target.id}", params: { user: { memberships: [
      { company_id: companies(:pro_co).id, role: "admin" }, { company_id: companies(:two).id, role: "owner" }
    ] } }, headers: super_admin_headers, as: :json

    assert_response :ok
    assert_equal "admin", target.role_in(companies(:pro_co))
    assert_equal "owner", target.role_in(companies(:two))
  end

  test "demoting the last owner saves nothing" do
    owner = users(:one_owner)

    patch "#{BASE}/#{owner.id}", params: { user: { first_name: "Cambiado", memberships: [ { company_id: companies(:one).id, role: "admin" } ] } },
                                 headers: super_admin_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "last_owner", json.dig("error", "details", "code")
    owner.reload
    assert_equal "Dueño", owner.first_name
    assert_equal "owner", owner.role_in(companies(:one))
  end

  test "an update without memberships leaves the companies alone" do
    target = users(:pro_staff)

    patch "#{BASE}/#{target.id}", params: { user: { phone: "5599990000" } }, headers: super_admin_headers, as: :json

    assert_response :ok
    assert_equal [ companies(:pro_co).id ], target.user_companies.reload.map(&:company_id)
    assert_equal "staff", target.role_in(companies(:pro_co))
  end

  test "role and company_ids are no longer read" do
    target = users(:pro_staff)

    patch "#{BASE}/#{target.id}", params: { user: { role: "owner", company_ids: [ companies(:two).id ] } },
                                  headers: super_admin_headers, as: :json

    assert_response :ok
    target.reload
    assert target.staff?
    assert_equal [ companies(:pro_co).id ], target.user_companies.map(&:company_id)
  end

  test "an update keeps the person active unless active changes" do
    target = users(:pro_staff)

    patch "#{BASE}/#{target.id}", params: { user: { first_name: "Otro" } }, headers: super_admin_headers, as: :json
    assert target.reload.active?

    patch "#{BASE}/#{target.id}", params: { user: { active: false } }, headers: super_admin_headers, as: :json
    assert_not target.reload.active?
  end

  test "the super admin creates a person with a role in a company" do
    sent = []
    ResendMailer.stub(:set_password, ->(**args) { sent << args; { "id" => "email_1" } }) do
      post BASE, params: { user: new_user_params(memberships: [ { company_id: companies(:pro_co).id, role: "admin" } ]) },
                 headers: super_admin_headers, as: :json
    end

    assert_response :created
    user = User.find_by!(email: "nueva@persona.test")
    assert_equal "admin", user.role_in(companies(:pro_co))
    assert_equal 1, sent.size
    assert_equal companies(:pro_co).name, sent.first[:company_name]
  end

  test "a new membership without role is staff" do
    ResendMailer.stub(:set_password, ->(**) { { "id" => "email_1" } }) do
      post BASE, params: { user: new_user_params(memberships: [ { company_id: companies(:pro_co).id } ]) },
                 headers: super_admin_headers, as: :json
    end

    assert_response :created
    assert_equal "staff", User.find_by!(email: "nueva@persona.test").role_in(companies(:pro_co))
  end

  test "creating with an invalid role creates nobody" do
    post BASE, params: { user: new_user_params(memberships: [ { company_id: companies(:pro_co).id, role: "super_admin" } ]) },
               headers: super_admin_headers, as: :json

    assert_response :bad_request
    assert_not User.exists?(email: "nueva@persona.test")
  end

  private

  def super_admin_headers
    auth_headers(users(:super_admin), companies(:pro_co))
  end

  def new_user_params(**extra)
    { first_name: "Nueva", last_name: "Persona", second_last_name: "Prueba", phone: "5511112222",
      email: "nueva@persona.test", active: true }.merge(extra)
  end

  def json
    JSON.parse(response.body)
  end
end
