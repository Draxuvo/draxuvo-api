require "test_helper"

# Spec 014 (data-model.md): la lista de membresías es el estado final completo.
class Users::SyncMembershipsTest < ActiveSupport::TestCase
  def sync(user, memberships)
    Users::SyncMemberships.new(user, memberships).call
  end

  def roles_of(user)
    user.user_companies.reload.to_h { |m| [ m.company_id, m.role ] }
  end

  test "creates, updates and removes memberships to match the list" do
    user = users(:pro_staff)

    sync(user, [ { company_id: companies(:pro_co).id, role: "admin" }, { company_id: companies(:two).id, role: "manager" } ])
    assert_equal({ companies(:pro_co).id => "admin", companies(:two).id => "manager" }, roles_of(user))

    sync(user, [ { company_id: companies(:two).id, role: "manager" } ])
    assert_equal({ companies(:two).id => "manager" }, roles_of(user))
  end

  test "a membership without role is staff" do
    user = users(:pro_staff)

    sync(user, [ { company_id: companies(:two).id }, { company_id: companies(:pro_co).id, role: "staff" } ])

    assert_equal "staff", roles_of(user)[companies(:two).id]
  end

  test "rejects super_admin and unknown roles without saving" do
    user = users(:pro_staff)

    %w[super_admin jefe].each do |role|
      error = assert_raises(ApiErrors::BadRequestError) do
        sync(user, [ { company_id: companies(:pro_co).id, role: role } ])
      end
      assert_equal({ role: role }, error.details)
    end
    assert_equal({ companies(:pro_co).id => "staff" }, roles_of(user))
  end

  test "rejects a company that does not exist" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      sync(users(:pro_staff), [ { company_id: 0, role: "staff" } ])
    end

    assert_equal "company_not_found", error.details[:code]
    assert_equal 0, error.details[:company_id]
  end

  test "rejects a company listed twice" do
    id = companies(:two).id
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      sync(users(:pro_staff), [ { company_id: id, role: "staff" }, { company_id: id, role: "admin" } ])
    end

    assert_equal "duplicate_company", error.details[:code]
    assert_equal id, error.details[:company_id]
  end

  test "does not demote or remove the only owner of a company" do
    owner = users(:one_owner)
    one = companies(:one).id

    [ [ { company_id: one, role: "admin" } ], [] ].each do |list|
      error = assert_raises(ApiErrors::UnprocessableEntityError) { sync(owner, list) }
      assert_equal "last_owner", error.details[:code]
      assert_equal one, error.details[:company_id]
      assert_equal I18n.t("company_members.last_owner"), error.message
    end
    assert_equal({ one => "owner" }, roles_of(owner))
  end

  test "demotes an owner when the company has another one" do
    sync(users(:pro_staff), [ { company_id: companies(:one).id, role: "owner" }, { company_id: companies(:pro_co).id, role: "staff" } ])

    sync(users(:one_owner), [ { company_id: companies(:one).id, role: "admin" } ])

    assert_equal "admin", roles_of(users(:one_owner))[companies(:one).id]
  end
end
