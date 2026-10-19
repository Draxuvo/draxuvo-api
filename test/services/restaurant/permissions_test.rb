require "test_helper"

class Restaurant::PermissionsTest < ActiveSupport::TestCase
  def context(user, role) = Restaurant::Permissions::Context.new(user: user, role: role)

  setup do
    @check = checks(:open_check) # mesero: resto_waiter
    @waiter = context(users(:resto_waiter), "staff")
    @other = context(users(:resto_waiter2), "staff")
    @boss = context(users(:resto_manager), "manager")
  end

  test "only the waiter of the check or a boss can charge it" do
    assert Restaurant::Permissions.pay?(@check, @waiter)
    assert_not Restaurant::Permissions.pay?(@check, @other)
    assert Restaurant::Permissions.pay?(@check, @boss)
  end

  test "a waiter cancels a new item but not one already in preparation" do
    assert Restaurant::Permissions.cancel_item?(check_items(:item_new), @waiter)
    assert_not Restaurant::Permissions.cancel_item?(check_items(:item_preparing), @waiter)
    assert Restaurant::Permissions.cancel_item?(check_items(:item_preparing), @boss)
  end

  test "another waiter cannot cancel a new item of a check that is not theirs" do
    assert_not Restaurant::Permissions.cancel_item?(check_items(:item_new), @other)
  end

  test "drafts and delivered items cannot be cancelled" do
    assert_not Restaurant::Permissions.cancel_item?(check_items(:item_draft), @boss)
    assert_not Restaurant::Permissions.cancel_item?(check_items(:closed_item), @boss)
  end

  test "item actions list deliver only when ready" do
    assert_equal %w[deliver cancel], Restaurant::Permissions.item_actions(check_items(:item_ready), @boss)
    assert_equal [], Restaurant::Permissions.item_actions(check_items(:item_draft), @boss)
  end

  test "check actions depend on the role and on what the check holds" do
    waiter_actions = Restaurant::Permissions.check_actions(@check, @waiter)
    other_actions = Restaurant::Permissions.check_actions(@check, @other)
    boss_actions = Restaurant::Permissions.check_actions(@check, @boss)

    assert_includes waiter_actions, "send", "tiene un artículo sin mandar"
    assert_includes waiter_actions, "pay"
    assert_not_includes other_actions, "pay"
    assert_includes other_actions, "add_item"
    assert_includes boss_actions, "reassign"
    assert_not_includes waiter_actions, "reassign"
  end

  test "an empty check can be cancelled by its waiter and a closed one has no actions" do
    empty = checks(:takeout_check)

    assert_includes Restaurant::Permissions.check_actions(empty, @other), "cancel"
    assert_empty Restaurant::Permissions.check_actions(checks(:closed_check), @boss)
  end
end
