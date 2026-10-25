require "test_helper"

class WorkOrders::TransitionTest < ActiveSupport::TestCase
  Transition = WorkOrders::Transition

  def ctx(role, user: users(:pro_co_owner), employee: nil)
    Transition::Context.new(user: user, role: role.to_s, employee: employee)
  end

  def boss = ctx(:admin)
  def admin = ctx(:admin)
  def owner = ctx(:owner)
  def worker = ctx(:staff, user: users(:pro_staff), employee: employees(:pro_staff_employee))
  def stranger = ctx(:staff, user: users(:pro_staff), employee: employees(:pro_other_employee))

  def last_event(order) = order.work_order_events.reload.last

  # --- tabla de reglas ---------------------------------------------------

  test "the rules table lists the six actions" do
    assert_equal %i[start finish reopen charge cancel void_charge], Transition::RULES.keys
    assert_equal %w[open], Transition::RULES[:start][:from]
    assert_equal %w[paid], Transition::RULES[:void_charge][:from]
    assert_equal :admin, Transition::RULES[:void_charge][:who]
    assert_equal :boss, Transition::RULES[:cancel][:who]
  end

  test "an unknown action raises bad request" do
    assert_raises(ApiErrors::BadRequestError) { Transition.call(work_orders(:pro_open), :explode, owner) }
  end

  # --- start / finish / reopen -------------------------------------------

  test "start moves an open order to in_progress and records the event" do
    order = Transition.call(work_orders(:pro_open), :start, worker)
    assert order.in_progress?
    assert_not_nil order.started_at
    assert_equal "started", last_event(order).kind
    assert_equal users(:pro_staff), last_event(order).actor
  end

  test "finish completes the order and reports pending steps" do
    order = Transition.call(work_orders(:pro_open), :finish, worker)
    assert order.done?
    assert_not_nil order.completed_at
    event = last_event(order)
    assert_equal "finished", event.kind
    assert_equal({ "pending_steps" => 2 }, event.data)
  end

  test "finish with every step done has no pending steps in the event" do
    work_orders(:pro_open).work_order_steps.each { |step| step.mark_done!(users(:pro_staff)) }
    order = Transition.call(work_orders(:pro_open), :finish, worker)
    assert_equal({}, last_event(order).data)
  end

  test "finish also works from in_progress" do
    assert Transition.call(work_orders(:pro_started), :finish, worker).done?
  end

  test "reopen sends a done order back to in_progress" do
    order = Transition.call(work_orders(:pro_done), :reopen, boss)
    assert order.in_progress?
    assert_nil order.completed_at
    assert_equal "reopened", last_event(order).kind
  end

  # --- origen inválido ---------------------------------------------------

  test "an invalid origin state raises 422 and changes nothing" do
    {
      start: :pro_started, finish: :pro_done, reopen: :pro_open, charge: :pro_open,
      cancel: :pro_paid, void_charge: :pro_done
    }.each do |action, fixture|
      order = work_orders(fixture)
      events_before = order.work_order_events.count
      error = assert_raises(ApiErrors::UnprocessableEntityError, "#{action} desde #{fixture}") do
        Transition.call(order, action, owner, { payment_method: "cash", amount_received: 5000, reason: "x" })
      end
      assert_equal I18n.t("work_order.invalid_transition"), error.message
      assert_equal order.status, error.details[:from]
      assert_equal events_before, order.work_order_events.count
    end
  end

  test "a cancelled order has no way out" do
    work_orders(:pro_cancelled).tap do |order|
      %i[start finish reopen charge cancel void_charge].each do |action|
        assert_raises(ApiErrors::UnprocessableEntityError) do
          Transition.call(order, action, owner, { payment_method: "cash", amount_received: 5000, reason: "x" })
        end
      end
    end
  end

  # --- roles -------------------------------------------------------------

  test "staff can act only on orders assigned to their employee" do
    assert_raises(ApiErrors::ForbiddenError) { Transition.call(work_orders(:pro_open), :start, stranger) }
    assert_raises(ApiErrors::ForbiddenError) { Transition.call(work_orders(:pro_unassigned), :start, worker) }
    assert_raises(ApiErrors::ForbiddenError) do
      Transition.call(work_orders(:pro_open), :start, ctx(:staff, user: users(:pro_staff), employee: nil))
    end
    assert_equal "open", work_orders(:pro_open).reload.status
  end

  test "bosses can act on any order" do
    assert Transition.call(work_orders(:pro_unassigned), :start, boss).in_progress?
  end

  test "cancel is for bosses, not for the assigned worker" do
    error = assert_raises(ApiErrors::ForbiddenError) { Transition.call(work_orders(:pro_open), :cancel, worker, { reason: "x" }) }
    assert_equal I18n.t("auth.not_authorized"), error.message
  end

  test "super_admin counts as admin and boss" do
    context = ctx(:super_admin, user: users(:super_admin))
    assert context.boss?
    assert context.admin?
    assert_not ctx(:staff).boss?
  end

  # --- cancel y void_charge ---------------------------------------------

  test "cancel needs a reason" do
    [ nil, "", "   " ].each do |reason|
      error = assert_raises(ApiErrors::UnprocessableEntityError) { Transition.call(work_orders(:pro_open), :cancel, boss, { reason: reason }) }
      assert_equal I18n.t("work_order.reason_required"), error.message
    end
    assert work_orders(:pro_open).reload.open?
  end

  test "cancel stores the reason on the order and in the event" do
    order = Transition.call(work_orders(:pro_open), :cancel, boss, { reason: "  Sin presupuesto " })
    assert order.cancelled?
    assert_equal "Sin presupuesto", order.cancel_reason
    assert_equal "cancelled", last_event(order).kind
    assert_equal({ "reason" => "Sin presupuesto" }, last_event(order).data)
  end

  test "cancel works from in_progress and done" do
    assert Transition.call(work_orders(:pro_started), :cancel, boss, { reason: "x" }).cancelled?
    assert Transition.call(work_orders(:pro_done), :cancel, boss, { reason: "x" }).cancelled?
  end

  test "void_charge needs a reason" do
    assert_raises(ApiErrors::UnprocessableEntityError) { Transition.call(work_orders(:pro_paid), :void_charge, admin, { reason: " " }) }
    assert work_orders(:pro_paid).reload.paid?
  end

  test "void_charge voids the ticket, reopens the order to done and logs the event" do
    order = Transition.call(work_orders(:pro_paid), :void_charge, owner, { reason: "Cobro duplicado" })
    ticket = order.ticket.reload
    assert order.done?
    assert ticket.voided?
    assert_equal "Cobro duplicado", ticket.void_reason
    assert_equal users(:pro_co_owner), ticket.voided_by
    assert_not_nil ticket.voided_at
    event = last_event(order)
    assert_equal "voided", event.kind
    assert_equal ticket.id, event.data["ticket_id"]
  end

  # --- cobro -------------------------------------------------------------

  test "charge rejects an invalid payment method" do
    [ nil, "", "bitcoin" ].each do |method|
      error = assert_raises(ApiErrors::UnprocessableEntityError) do
        Transition.call(work_orders(:pro_done), :charge, boss, { payment_method: method })
      end
      assert_equal I18n.t("ticket.invalid_payment_method"), error.message
    end
    assert_nil work_orders(:pro_done).reload.ticket
  end

  test "charge rejects an order without priced items" do
    order = work_orders(:pro_done)
    order.work_order_items.destroy_all
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      Transition.call(order, :charge, boss, { payment_method: "card" })
    end
    assert_equal I18n.t("work_order.no_items"), error.message
    assert_equal({ reason: "no_items" }, error.details)
  end

  test "charge rejects an order whose items have no price" do
    order = work_orders(:pro_done)
    order.work_order_items.update_all(unit_price: nil)
    assert_raises(ApiErrors::UnprocessableEntityError) do
      Transition.call(order, :charge, boss, { payment_method: "card" })
    end
  end

  test "cash below the total is rejected and reports what is missing" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      Transition.call(work_orders(:pro_done), :charge, boss, { payment_method: "cash", amount_received: "800" })
    end
    assert_equal I18n.t("ticket.insufficient_cash"), error.message
    assert_equal "50.0", error.details[:missing]
    assert work_orders(:pro_done).reload.done?
    assert_nil work_orders(:pro_done).ticket
  end

  test "cash with a missing or non numeric amount counts as zero" do
    [ nil, "mucho" ].each do |amount|
      assert_raises(ApiErrors::UnprocessableEntityError) do
        Transition.call(work_orders(:pro_done), :charge, boss, { payment_method: "cash", amount_received: amount })
      end
    end
  end

  test "charging in cash computes the change and creates the ticket and event" do
    order = Transition.call(work_orders(:pro_done), :charge, worker_for_done, { payment_method: "cash", amount_received: "1000" })
    ticket = order.ticket
    assert order.paid?
    assert ticket.paid?
    assert ticket.cash?
    assert_equal 850, ticket.total
    assert_equal 1000, ticket.amount_received
    assert_equal 150, ticket.change_given
    assert_equal users(:pro_staff), ticket.charged_by
    assert_not_nil ticket.paid_at
    assert_match(/\AT-\d{6,}\z/, ticket.folio)
    event = last_event(order)
    assert_equal "charged", event.kind
    assert_equal ticket.folio, event.data["folio"]
    assert_equal "150.0", event.data["change_given"]
    assert_equal "cash", event.data["payment_method"]
  end

  # La orden pro_done es del técnico pro_other_employee: el contexto tiene que ser de ese empleado.
  def worker_for_done = ctx(:staff, user: users(:pro_staff), employee: employees(:pro_other_employee))

  test "charging by card needs no amount and receives the total" do
    order = Transition.call(work_orders(:pro_done), :charge, boss, { payment_method: "card" })
    assert_equal 850, order.ticket.amount_received
    assert_equal 0, order.ticket.change_given
  end

  test "charging recalculates the total from the items" do
    order = work_orders(:pro_done)
    order.update_column(:total, 1)
    assert_equal 850, Transition.call(order, :charge, boss, { payment_method: "transfer" }).ticket.total
  end

  test "charge accepts string keys and ActionController parameters" do
    params = ActionController::Parameters.new(payment_method: "card")
    assert Transition.call(work_orders(:pro_done), :charge, boss, params).paid?
    assert Transition.call(work_orders(:pro_open).tap { |o| o.update_columns(status: 2) }, :charge, boss, { "payment_method" => "card" }).paid?
  end

  test "charging again after a void reuses the same ticket and folio" do
    order = Transition.call(work_orders(:pro_done), :charge, boss, { payment_method: "card" })
    folio = order.ticket.folio
    Transition.call(order, :void_charge, admin, { reason: "Error" })
    assert_no_difference -> { Ticket.count } do
      order = Transition.call(order.reload, :charge, boss, { payment_method: "cash", amount_received: 900 })
    end
    ticket = order.ticket.reload
    assert_equal folio, ticket.folio
    assert ticket.paid?
    assert ticket.cash?
    assert_nil ticket.voided_at
    assert_nil ticket.voided_by
    assert_nil ticket.void_reason
    assert_equal 50, ticket.change_given
    assert_equal %w[charged voided charged], order.work_order_events.where(kind: %i[charged voided]).map(&:kind)
  end

  test "if the charge fails after the ticket is saved, everything rolls back" do
    order = work_orders(:pro_done)
    # Empleado de otra empresa: el update! final de la orden falla después de guardar el ticket.
    order.update_column(:employee_id, employees(:one).id)
    assert_no_difference [ "Ticket.count", "WorkOrderEvent.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) { Transition.call(order, :charge, boss, { payment_method: "card" }) }
    end
    assert order.reload.done?
  end

  # --- .allowed ----------------------------------------------------------

  test "allowed lists the actions a worker can run on an assigned order" do
    assert_equal %i[start finish], Transition.allowed(work_orders(:pro_open), worker)
    assert_equal %i[finish], Transition.allowed(work_orders(:pro_started), worker)
    assert_equal [], Transition.allowed(work_orders(:pro_open), stranger)
  end

  test "allowed gives a boss cancel as well and an admin void_charge on paid orders" do
    assert_equal %i[start finish cancel], Transition.allowed(work_orders(:pro_open), boss)
    assert_equal %i[reopen charge cancel], Transition.allowed(work_orders(:pro_done), boss)
    assert_equal [], Transition.allowed(work_orders(:pro_paid), worker)
    assert_equal %i[void_charge], Transition.allowed(work_orders(:pro_paid), admin)
  end

  test "allowed is empty for a cancelled order" do
    assert_equal [], Transition.allowed(work_orders(:pro_cancelled), owner)
  end
end
