require "test_helper"

class Restaurant::AdvanceItemsTest < ActiveSupport::TestCase
  setup do
    @kitchen = stations(:kitchen)
    @bar = stations(:bar)
  end

  test "moves an item one step and stamps the time" do
    item, = Restaurant::AdvanceItems.item(@kitchen, check_items(:item_new).id)

    assert item.status_preparing?
    assert item.preparing_at.present?
  end

  test "preparing becomes ready with its timestamp" do
    item, = Restaurant::AdvanceItems.item(@kitchen, check_items(:item_preparing).id)

    assert item.status_ready?
    assert item.ready_at.present?
  end

  test "a ready item cannot advance again" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) { Restaurant::AdvanceItems.item(@bar, check_items(:item_ready).id) }

    assert_equal "invalid_transition", error.details[:code]
  end

  test "a station cannot advance the items of another station" do
    assert_raises(ActiveRecord::RecordNotFound) { Restaurant::AdvanceItems.item(@bar, check_items(:item_new).id) }
  end

  test "an item of a check that is no longer open does not advance" do
    check_items(:item_new).check.update!(status: :cancelled, closed_at: Time.current)

    assert_raises(ApiErrors::UnprocessableEntityError) { Restaurant::AdvanceItems.item(@kitchen, check_items(:item_new).id) }
  end

  test "marking a whole round moves each item one step" do
    items = Restaurant::AdvanceItems.order(@kitchen, kitchen_orders(:first_round).id)

    assert_equal %w[preparing ready], items.map(&:status).sort_by { |s| %w[preparing ready].index(s) }
  end

  test "marking a round with nothing left to do fails" do
    Restaurant::AdvanceItems.order(@bar, kitchen_orders(:first_round).id) # solo la cola, ya lista
  rescue ApiErrors::UnprocessableEntityError => e
    assert_equal "invalid_transition", e.details[:code]
  else
    flunk "debía fallar: no queda nada pendiente en la barra"
  end

  test "other stations are untouched when one marks the round" do
    Restaurant::AdvanceItems.order(@kitchen, kitchen_orders(:first_round).id)

    assert check_items(:item_ready).reload.status_ready?
  end
end
