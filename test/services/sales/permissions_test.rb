require "test_helper"

class Sales::PermissionsTest < ActiveSupport::TestCase
  def context(user, role) = Sales::Permissions::Context.new(user: user, role: role)

  setup do
    @sale = open_sale(users(:pos_staff))
  end

  test "the opener, an admin and an owner can access an open sale; another cashier cannot" do
    assert Sales::Permissions.access?(@sale, context(users(:pos_staff), "staff"))
    assert Sales::Permissions.access?(@sale, context(users(:pos_admin), "admin"))
    assert Sales::Permissions.access?(@sale, context(users(:pos_owner), "owner"))
    assert_not Sales::Permissions.access?(@sale, context(users(:pos_staff2), "staff"))
  end

  test "only an open sale can be discarded, by its opener or a boss" do
    assert Sales::Permissions.discard?(@sale, context(users(:pos_staff), "staff"))
    assert Sales::Permissions.discard?(@sale, context(users(:pos_admin), "admin"))
    assert_not Sales::Permissions.discard?(@sale, context(users(:pos_staff2), "staff"))
    @sale.update!(status: :paid, paid_at: Time.current, charged_by: users(:pos_staff))
    assert_not Sales::Permissions.discard?(@sale, context(users(:pos_admin), "admin"))
  end

  test "only owner and admin can cancel" do
    assert Sales::Permissions.cancel?(@sale, context(users(:pos_owner), "owner"))
    assert Sales::Permissions.cancel?(@sale, context(users(:pos_admin), "admin"))
    assert_not Sales::Permissions.cancel?(@sale, context(users(:pos_staff), "staff"))
  end

  test "actions depend on the state and the role" do
    staff = context(users(:pos_staff), "staff")
    boss = context(users(:pos_admin), "admin")
    assert_equal %w[add_item charge discard], Sales::Permissions.actions(@sale, staff)
    assert_empty Sales::Permissions.actions(@sale, context(users(:pos_staff2), "staff"))

    @sale.update!(status: :paid, paid_at: Time.current, charged_by: users(:pos_staff))
    assert_equal %w[ticket], Sales::Permissions.actions(@sale, staff)
    assert_equal %w[ticket cancel], Sales::Permissions.actions(@sale, boss)
  end
end
