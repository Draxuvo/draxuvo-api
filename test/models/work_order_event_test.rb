require "test_helper"

class WorkOrderEventTest < ActiveSupport::TestCase
  def build_event(**attrs)
    WorkOrderEvent.new({ work_order: work_orders(:pro_open), actor: users(:pro_co_owner), kind: :note,
                         data: { "text" => "Llamar al cliente" } }.merge(attrs))
  end

  test "a note with text is valid" do
    assert build_event.valid?
  end

  test "a note needs text of at most 2000 characters" do
    [ { "text" => "" }, { "text" => "   " }, {}, { "otro" => "x" } ].each do |data|
      event = build_event(data: data)
      assert_not event.valid?, "#{data.inspect} debería ser inválido"
      assert event.errors[:data].any?
    end
    assert build_event(data: { "text" => "a" * 2000 }).valid?
    assert_not build_event(data: { "text" => "a" * 2001 }).valid?
  end

  test "other kinds do not need text" do
    assert build_event(kind: :started, data: {}).valid?
  end

  test "an unknown kind is invalid instead of raising" do
    event = build_event(kind: "inventado")
    assert_not event.valid?
    assert event.errors[:kind].any?
  end

  test "data cannot be nil" do
    assert_not build_event(kind: :started, data: nil).valid?
  end

  test "all kinds are exposed" do
    assert_equal %w[created started finished reopened charged voided cancelled reassigned note photo],
                 WorkOrderEvent.kinds.keys
  end

  test "an event cannot be updated" do
    event = build_event.tap(&:save!)
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update(data: { "text" => "Cambio" }) }
  end

  test "a lone event cannot be destroyed" do
    event = work_order_events(:pro_open_created)
    assert_not event.destroy
    assert WorkOrderEvent.exists?(event.id)
  end

  test "destroying the order removes its events" do
    order = work_orders(:pro_started)
    assert_difference -> { WorkOrderEvent.count }, -2 do
      order.destroy!
    end
  end

  test "an order lists events oldest first" do
    kinds = work_orders(:pro_started).work_order_events.map(&:kind)
    assert_equal %w[created started], kinds
  end
end
