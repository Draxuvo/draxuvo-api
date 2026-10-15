require "test_helper"

class WorkOrderTest < ActiveSupport::TestCase
  def build_order(**attrs)
    WorkOrder.new({ company: companies(:pro_co), created_by: users(:pro_co_owner), title: "Orden nueva" }.merge(attrs))
  end

  test "title is required and priority/status have defaults" do
    assert_not build_order(title: "").valid?
    order = build_order
    assert order.valid?
    assert order.medium?
    assert order.open?
  end

  test "total comes from the sum of item subtotals" do
    order = work_orders(:pro_open)
    assert_equal 600, order.reload.total
    order.work_order_items.create!(description: "Extra", quantity: 2, unit_price: 50, position: 5)
    assert_equal 700, order.reload.total
    order.work_order_items.find_by(description: "Extra").destroy!
    assert_equal 600, order.reload.total
  end

  test "recalculate_total! ignores items without price" do
    order = work_orders(:pro_open)
    order.work_order_items.create!(description: "Sin precio", position: 9)
    order.recalculate_total!
    assert_equal 600, order.reload.total
  end

  test "progress is the percentage of steps done" do
    assert_equal 0, work_orders(:pro_open).progress
    assert_equal 50, work_orders(:pro_started).progress
    assert_equal 0, work_orders(:pro_unassigned).progress
    order = work_orders(:pro_open)
    order.work_order_steps.each { |step| step.mark_done!(users(:pro_staff)) }
    assert_equal 100, order.reload.progress
  end

  test "progress rounds to a whole number" do
    order = work_orders(:pro_open)
    order.work_order_steps.create!(description: "Tercero", position: 2)
    order.work_order_steps.first.mark_done!(users(:pro_staff))
    assert_equal 33, order.reload.progress
  end

  test "locked? is true for paid and cancelled orders only" do
    assert work_orders(:pro_paid).locked?
    assert work_orders(:pro_cancelled).locked?
    assert_not work_orders(:pro_open).locked?
    assert_not work_orders(:pro_done).locked?
  end

  test "customer phone accepts digits, spaces and symbols and 7 to 20 characters" do
    assert build_order(customer_phone: "+52 (55) 1234-5678").valid?
    assert build_order(customer_phone: "").valid?
    assert_not build_order(customer_phone: "abc12345").valid?
    assert_not build_order(customer_phone: "123456").valid?
    assert_not build_order(customer_phone: "1" * 21).valid?
  end

  test "a cancelled order needs a reason" do
    order = build_order(status: :cancelled)
    assert_not order.valid?
    assert order.errors[:cancel_reason].any?
    order.cancel_reason = "Sin presupuesto"
    assert order.valid?
  end

  test "employee must belong to the same company" do
    order = build_order(employee: employees(:one))
    assert_not order.valid?
    assert order.errors[:employee].any?
    assert build_order(employee: employees(:pro_staff_employee)).valid?
    assert build_order(employee: nil).valid?
  end

  test "a paid order rejects changes" do
    order = work_orders(:pro_paid)
    assert_not order.update(title: "Otro título")
    assert order.errors[:base].any?
    assert_equal "Lámparas de sala", order.reload.title
  end

  test "a cancelled order has no way out" do
    order = work_orders(:pro_cancelled)
    assert_not order.update(status: :open)
    assert_equal "cancelled", order.reload.status
  end

  test "a paid order may go back to done and nothing else" do
    order = work_orders(:pro_paid)
    assert order.update(status: :done)
    assert order.reload.done?
  end

  test "a paid order cannot go to done and change another column at once" do
    order = work_orders(:pro_paid)
    assert_not order.update(status: :done, title: "Cambio")
    assert order.reload.paid?
  end

  test "search matches title or description" do
    assert_includes WorkOrder.search("contactos"), work_orders(:pro_open)
    assert_includes WorkOrder.search("cocina"), work_orders(:pro_open)
    assert_not_includes WorkOrder.search("contactos"), work_orders(:pro_done)
    assert_equal WorkOrder.count, WorkOrder.search("").count
  end

  test "aliases point to the associations" do
    order = work_orders(:pro_started)
    assert_equal order.work_order_steps.to_a, order.steps.to_a
    assert_equal order.work_order_events.to_a, order.events.to_a
    assert_equal order.work_order_attachments.to_a, order.attachments.to_a
  end

  test "destroying an order removes its dependents" do
    order = work_orders(:pro_open)
    order.destroy!
    assert_equal 0, WorkOrderItem.where(work_order_id: order.id).count
    assert_equal 0, WorkOrderStep.where(work_order_id: order.id).count
    assert_equal 0, WorkOrderEvent.where(work_order_id: order.id).count
  end
end
