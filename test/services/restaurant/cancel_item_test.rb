require "test_helper"

class Restaurant::CancelItemTest < ActiveSupport::TestCase
  setup do
    @waiter = Restaurant::Permissions::Context.new(user: users(:resto_waiter), role: "staff")
    @other = Restaurant::Permissions::Context.new(user: users(:resto_waiter2), role: "staff")
    @boss = Restaurant::Permissions::Context.new(user: users(:resto_owner), role: "owner")
  end

  def code_of
    yield
    flunk "debía fallar"
  rescue ApiErrors::UnprocessableEntityError => e
    e.details[:code]
  end

  test "the waiter of the check cancels a new item with a reason" do
    item = Restaurant::CancelItem.call(check_items(:item_new), @waiter, "El cliente cambió de idea")

    assert item.status_cancelled?
    assert_equal "El cliente cambió de idea", item.cancel_reason
    assert_equal users(:resto_waiter), item.cancelled_by
    assert item.cancelled_at.present?
  end

  test "the total drops by what was cancelled" do
    checks(:open_check).recalculate_total!
    before = checks(:open_check).reload.total
    Restaurant::CancelItem.call(check_items(:item_new), @waiter, "x")

    assert_equal before - 70, checks(:open_check).reload.total
  end

  test "a waiter cannot cancel what is already in preparation, a boss can" do
    assert_raises(ApiErrors::ForbiddenError) { Restaurant::CancelItem.call(check_items(:item_preparing), @waiter, "x") }
    assert check_items(:item_preparing).reload.status_preparing?

    assert Restaurant::CancelItem.call(check_items(:item_preparing), @boss, "Se quemó").status_cancelled?
  end

  test "only a boss cancels something ready" do
    assert_raises(ApiErrors::ForbiddenError) { Restaurant::CancelItem.call(check_items(:item_ready), @waiter, "x") }
    assert Restaurant::CancelItem.call(check_items(:item_ready), @boss, "x").status_cancelled?
  end

  test "another waiter cannot cancel an item of a check that is not theirs" do
    assert_raises(ApiErrors::ForbiddenError) { Restaurant::CancelItem.call(check_items(:item_new), @other, "x") }
  end

  test "a reason is required" do
    assert_equal "reason_required", code_of { Restaurant::CancelItem.call(check_items(:item_new), @waiter, "  ") }
    assert check_items(:item_new).reload.status_new?
  end

  test "drafts, delivered and already cancelled items are not cancelled this way" do
    assert_equal "invalid_transition", code_of { Restaurant::CancelItem.call(check_items(:item_draft), @boss, "x") }
    check_items(:item_ready).update!(status: :delivered, delivered_at: Time.current)
    assert_equal "invalid_transition", code_of { Restaurant::CancelItem.call(check_items(:item_ready), @boss, "x") }
    Restaurant::CancelItem.call(check_items(:item_new), @boss, "x")
    assert_equal "invalid_transition", code_of { Restaurant::CancelItem.call(check_items(:item_new), @boss, "x") }
  end

  test "an item of a check that is not open cannot be cancelled" do
    assert_equal "check_not_open", code_of { Restaurant::CancelItem.call(check_items(:closed_item), @boss, "x") }
  end

  test "a cancelled item no longer commits stock" do
    committed_before = Restaurant::Availability.new(companies(:resto_co)).committed.fetch(products(:resto_tacos).id)
    Restaurant::CancelItem.call(check_items(:item_new), @waiter, "x")
    after = Restaurant::Availability.new(companies(:resto_co)).committed.fetch(products(:resto_tacos).id, 0)

    assert_equal committed_before - 1, after
  end
end
