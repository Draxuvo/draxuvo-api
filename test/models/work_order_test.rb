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

  # --- Spec 054: prioridad, fecha límite y longitudes ---

  def build_order(**attrs) = WorkOrder.new({ company: companies(:pro_co), title: "Orden", created_by: users(:pro_co_owner) }.merge(attrs))

  test "an invalid priority is a validation error, not an exception" do
    order = build_order(priority: "urgentisima")
    assert_not order.valid?
    assert_includes order.errors.attribute_names, :priority
    assert build_order(priority: "high").valid?
  end

  test "a due date that is not a date is rejected and a blank one is not" do
    order = build_order(due_date: "no-es-fecha")
    assert_not order.valid?
    assert_includes order.errors.attribute_names, :due_date
    assert build_order(due_date: "").valid?
    assert build_order(due_date: nil).valid?
    assert build_order(due_date: "2026-12-31").valid?
    assert build_order(due_date: Date.new(2026, 12, 31)).valid?
  end

  test "free text fields have a maximum length that accepts the limit and rejects one more" do
    { title: 200, customer_name: 120, customer_address: 300, notes: 2000 }.each do |field, max|
      assert build_order(field => "x" * max).valid?, "#{field} con #{max}"
      order = build_order(field => "x" * (max + 1))
      assert_not order.valid?, "#{field} con #{max + 1}"
      assert_includes order.errors.attribute_names, field
    end
  end

  test "an old order with a longer text can still be updated without touching it" do
    order = work_orders(:pro_open)
    order.update_columns(notes: "x" * 5000, customer_name: "y" * 500)
    assert order.reload.update(priority: :high), order.errors.full_messages.to_sentence
    assert_not order.update(notes: "z" * 5000)
  end
end
