require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/company/members"). FR-020, FR-021, FR-026.
class Api::V1::CompanyMembersControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/company/members".freeze

  setup do
    @company = companies(:pro_co)
    @admin = create_member(@company, role: :admin)
  end

  # --- GET -------------------------------------------------------------------------------------

  test "index lists only the members of the active company with their role there" do
    create_member(companies(:one), role: :staff, user: users(:pro_staff))

    get BASE, headers: auth_headers(users(:pro_co_owner), @company)

    assert_response :ok
    members = json["results"].index_by { |m| m["id"] }
    assert_equal [ users(:pro_co_owner), users(:pro_staff), @admin ].map(&:id).sort, members.keys.sort
    assert_equal "owner", members[users(:pro_co_owner).id]["role"]
    assert_equal "admin", members[@admin.id]["role"]
    %w[first_name last_name email active].each { |key| assert members[@admin.id].key?(key), "missing #{key}" }
    assert_not members.key?(users(:one_owner).id)
  end

  test "admins can list, staff cannot" do
    get BASE, headers: auth_headers(@admin, @company)
    assert_response :ok

    get BASE, headers: auth_headers(users(:pro_staff), @company)
    assert_response :forbidden
  end

  # --- POST ------------------------------------------------------------------------------------

  test "an admin invites a new person with a role up to its own" do
    assert_difference [ "User.count", "UserCompany.count" ], 1 do
      post BASE, params: { member: { email: "nuevo@pro-co.test", first_name: "Nuevo", last_name: "Miembro",
                                     phone: "5511111111", role: "admin" } },
                 headers: auth_headers(@admin, @company), as: :json
    end

    assert_response :created
    assert_equal "admin", json["role"]
    user = User.find_by!(email: "nuevo@pro-co.test")
    assert_equal "admin", user.user_companies.find_by!(company: @company).role
    assert_not user.super_admin?
  end

  test "inviting a new person reports whether the email went out" do
    sent = { success: true }
    Email::SetPasswordService.stub(:new, ->(*, **) { Struct.new(:call).new(sent) }) do
      post BASE, params: { member: { email: "nuevo@pro-co.test", first_name: "Nuevo", last_name: "Miembro", phone: "5511111111", role: "staff" } }, headers: auth_headers(@admin, @company), as: :json
    end
    assert_response :created
    assert_equal true, json["email_sent"]

    sent = { success: false, error: "Resend rechazó el remitente" }
    Email::SetPasswordService.stub(:new, ->(*, **) { Struct.new(:call).new(sent) }) do
      post BASE, params: { member: { email: "otro@pro-co.test", first_name: "Otro", last_name: "Miembro", phone: "5522222222", role: "staff" } }, headers: auth_headers(@admin, @company), as: :json
    end
    assert_response :created, "la persona queda dada de alta aunque el correo falle"
    assert_equal false, json["email_sent"]
  end

  test "an admin cannot invite an owner or a super admin" do
    %w[owner super_admin].each do |role|
      assert_no_difference [ "User.count", "UserCompany.count" ] do
        post BASE, params: { member: { email: "#{role}@pro-co.test", first_name: "A", last_name: "B", phone: "1", role: role } },
                   headers: auth_headers(@admin, @company), as: :json
      end
      assert_response :forbidden, "#{role} should be rejected"
    end
  end

  test "even an owner cannot assign super_admin" do
    post BASE, params: { member: { email: "sa@pro-co.test", first_name: "A", last_name: "B", phone: "1", role: "super_admin" } },
               headers: auth_headers(users(:pro_co_owner), @company), as: :json

    assert_response :forbidden
    assert_not User.exists?(email: "sa@pro-co.test")
  end

  test "inviting an existing user only creates the membership" do
    existing = users(:one_owner)

    assert_no_difference "User.count" do
      assert_difference "UserCompany.count", 1 do
        post BASE, params: { member: { email: existing.email, role: "staff" } },
                   headers: auth_headers(@admin, @company), as: :json
      end
    end

    assert_response :created
    assert_equal "staff", existing.user_companies.find_by!(company: @company).role
    assert_equal "owner", existing.user_companies.find_by!(company: companies(:one)).role
  end

  test "inviting someone who is already a member answers 422" do
    post BASE, params: { member: { email: users(:pro_staff).email, role: "staff" } },
               headers: auth_headers(@admin, @company), as: :json

    assert_response :unprocessable_entity
    assert_equal "already_member", json.dig("error", "details", "code")
  end

  # --- PATCH -----------------------------------------------------------------------------------

  test "an admin changes a role only for the active company" do
    create_member(companies(:one), role: :staff, user: users(:pro_staff))

    patch "#{BASE}/#{users(:pro_staff).id}", params: { member: { role: "admin" } },
                                              headers: auth_headers(@admin, @company), as: :json

    assert_response :ok
    assert_equal "admin", json["role"]
    assert_equal "admin", users(:pro_staff).user_companies.find_by!(company: @company).role
    assert_equal "staff", users(:pro_staff).user_companies.find_by!(company: companies(:one)).role
  end

  test "an admin cannot promote above itself, touch an owner or assign super_admin" do
    patch "#{BASE}/#{users(:pro_staff).id}", params: { member: { role: "owner" } },
                                              headers: auth_headers(@admin, @company), as: :json
    assert_response :forbidden

    patch "#{BASE}/#{users(:pro_co_owner).id}", params: { member: { role: "staff" } },
                                                 headers: auth_headers(@admin, @company), as: :json
    assert_response :forbidden

    patch "#{BASE}/#{users(:pro_staff).id}", params: { member: { role: "super_admin" } },
                                              headers: auth_headers(users(:pro_co_owner), @company), as: :json
    assert_response :forbidden

    assert_equal "staff", users(:pro_staff).user_companies.find_by!(company: @company).role
    assert_equal "owner", users(:pro_co_owner).user_companies.find_by!(company: @company).role
    assert_not users(:pro_staff).reload.super_admin?
  end

  test "only an owner assigns owner" do
    patch "#{BASE}/#{users(:pro_staff).id}", params: { member: { role: "owner" } },
                                                headers: auth_headers(users(:pro_co_owner), @company), as: :json

    assert_response :ok
    assert_equal "owner", users(:pro_staff).user_companies.find_by!(company: @company).role
  end

  test "the last owner cannot be demoted" do
    patch "#{BASE}/#{users(:pro_co_owner).id}", params: { member: { role: "admin" } },
                                                 headers: auth_headers(users(:pro_co_owner), @company), as: :json

    assert_response :unprocessable_entity
    assert_equal "last_owner", json.dig("error", "details", "code")
    assert_equal "owner", users(:pro_co_owner).user_companies.find_by!(company: @company).role
  end

  test "a member of another company is not found" do
    patch "#{BASE}/#{users(:one_owner).id}", params: { member: { role: "staff" } },
                                              headers: auth_headers(users(:pro_co_owner), @company), as: :json

    assert_response :not_found
    assert_equal "owner", users(:one_owner).user_companies.find_by!(company: companies(:one)).role
  end

  # --- DELETE ----------------------------------------------------------------------------------

  test "removing a member deletes the membership, not the user" do
    assert_difference "UserCompany.count", -1 do
      delete "#{BASE}/#{users(:pro_staff).id}", headers: auth_headers(@admin, @company)
    end

    assert_response :ok
    assert User.exists?(users(:pro_staff).id)
  end

  test "an admin cannot remove an owner and the last owner cannot be removed" do
    delete "#{BASE}/#{users(:pro_co_owner).id}", headers: auth_headers(@admin, @company)
    assert_response :forbidden

    delete "#{BASE}/#{users(:pro_co_owner).id}", headers: auth_headers(users(:pro_co_owner), @company)
    assert_response :unprocessable_entity
    assert_equal "last_owner", json.dig("error", "details", "code")

    assert users(:pro_co_owner).user_companies.exists?(company: @company)
  end

  private

  def json
    JSON.parse(response.body)
  end

  # --- super admin (spec 029) ------------------------------------------------------------------

  test "a super admin can demote the last owner" do
    patch "#{BASE}/#{users(:pro_co_owner).id}", params: { member: { role: "admin" } },
                                                 headers: auth_headers(users(:super_admin), @company), as: :json

    assert_response :ok
    assert_equal "admin", users(:pro_co_owner).user_companies.find_by!(company: @company).role
  end

  test "a super admin can remove the last owner" do
    assert_difference -> { @company.user_companies.count }, -1 do
      delete "#{BASE}/#{users(:pro_co_owner).id}", headers: auth_headers(users(:super_admin), @company)
    end

    assert_response :ok
    assert_not @company.user_companies.owner.exists?
  end

  test "a super admin can assign the owner role but never super_admin" do
    patch "#{BASE}/#{@admin.id}", params: { member: { role: "owner" } },
                                   headers: auth_headers(users(:super_admin), @company), as: :json
    assert_response :ok
    assert_equal "owner", json["role"]

    patch "#{BASE}/#{@admin.id}", params: { member: { role: "super_admin" } },
                                   headers: auth_headers(users(:super_admin), @company), as: :json
    assert_response :forbidden
    assert_equal "role_not_allowed", json.dig("error", "details", "code")
  end
end
