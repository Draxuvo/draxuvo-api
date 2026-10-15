require "test_helper"

class WorkOrderStepTest < ActiveSupport::TestCase
  def build_step(**attrs)
    WorkOrderStep.new({ work_order: work_orders(:pro_open), description: "Revisar tablero", position: 2 }.merge(attrs))
  end

  test "description is required and limited to 255 characters" do
    assert build_step.valid?
    assert_not build_step(description: "").valid?
    assert build_step(description: "a" * 255).valid?
    assert_not build_step(description: "a" * 256).valid?
  end

  test "position cannot be negative" do
    assert build_step(position: 0).valid?
    step = build_step(position: -1)
    assert_not step.valid?
    assert step.errors[:position].any?
  end

  test "mark_done! fills done_at and done_by" do
    step = build_step.tap(&:save!)
    assert_not step.done?
    step.mark_done!(users(:pro_staff))
    assert step.reload.done?
    assert_equal users(:pro_staff), step.done_by
    assert_not_nil step.done_at
  end

  test "mark_undone! clears done_at and done_by" do
    step = work_order_steps(:pro_started_step_1)
    assert step.done?
    step.mark_undone!
    assert_not step.reload.done?
    assert_nil step.done_by
  end

  test "a step belongs to a work order" do
    assert_not build_step(work_order: nil).valid?
  end

  test "an order lists its steps by position" do
    assert_equal [ 0, 1 ], work_orders(:pro_open).work_order_steps.map(&:position)
  end
end
