# app/serializers/work_order_serializer.rb
# `context` (WorkOrders::Transition::Context) permite calcular allowed_actions; sin él se omiten.
class WorkOrderSerializer
  def initialize(order, detailed: false, context: nil)
    @order    = order
    @detailed = detailed
    @context  = context
  end

  def as_json(*)
    steps = @order.work_order_steps.to_a
    base = {
      id:           @order.id,
      title:        @order.title,
      description:  @order.description,
      priority:     @order.priority,
      priority_label: I18n.t("work_order.priority.#{@order.priority}"),
      status:       @order.status,
      status_label: I18n.t("work_order.status.#{@order.status}"),
      due_date:     @order.due_date,
      completed_at: @order.completed_at,
      notes:        @order.notes,
      progress:     @order.progress,
      total:        @order.total,
      created_at:   @order.created_at,
      customer_name:    @order.customer_name,
      customer_phone:   @order.customer_phone,
      customer_address: @order.customer_address,
      employee:     @order.employee ? { id: @order.employee.id, name: @order.employee.name } : nil,
      items_count:  @order.work_order_items.size,
      steps_count:  steps.size,
      steps_done:   steps.count { |s| s.done_at.present? }
    }

    base.merge!(detail(steps)) if @detailed
    base
  end

  private

  def detail(steps)
    {
      items:  @order.work_order_items.map { |item| item_json(item) },
      steps:  steps.map { |step| step_json(step) },
      photos: @order.work_order_attachments.includes(file_attachment: :blob).map { |photo| photo_json(photo) },
      events: @order.work_order_events.map { |event| event_json(event) },
      ticket: @order.ticket ? TicketSerializer.person_ticket(@order.ticket) : nil,
      allowed_actions: allowed_actions,
      charge_blocked_reason: charge_blocked_reason,
      cancel_reason: @order.cancel_reason
    }
  end

  def item_json(item)
    {
      id: item.id, description: item.description, quantity: item.quantity, unit: item.unit,
      unit_price: item.unit_price, subtotal: item.subtotal, position: item.position,
      product: item.product ? { id: item.product.id, sku: item.product.sku, name: item.product.name,
                                category: item.product.category } : nil
    }
  end

  def step_json(step)
    { id: step.id, description: step.description, position: step.position, done: step.done_at.present?,
      done_at: step.done_at, done_by: person(step.done_by) }
  end

  def photo_json(photo)
    { id: photo.id, url: photo.file.attached? ? Rails.application.routes.url_helpers.rails_blob_url(photo.file) : nil,
      description: photo.description, uploaded_by: person(photo.uploaded_by), created_at: photo.created_at }
  end

  def event_json(event)
    { id: event.id, kind: event.kind, actor: person(event.actor), data: event_data(event), created_at: event.created_at }
  end

  def event_data(event)
    data = event.data || {}
    return data unless event.reassigned?

    { from: employee_ref(data["from_employee_id"]), to: employee_ref(data["to_employee_id"]) }
  end

  def employee_ref(id)
    employee = id && Employee.find_by(id: id)
    employee ? { id: employee.id, name: employee.name } : nil
  end

  def person(record)
    TicketSerializer.person(record)
  end

  # Qué puede hacer la persona ahora mismo con esta orden (la UI solo pinta lo que viene aquí).
  def allowed_actions
    return [] unless @context

    ctx = @context
    order = @order
    boss = ctx.boss?
    worker = boss || ctx.assigned_to?(order)
    open_order = !order.locked?
    actions = WorkOrders::Transition.allowed(order, ctx).map(&:to_s)
    actions.delete("charge") if charge_blocked_reason
    actions << "edit" << "edit_items" << "edit_steps" if boss && open_order
    actions << "delete" if ctx.admin? && open_order
    service = order.company.order_mode_service?
    actions << "add_item" if open_order && (boss || (ctx.assigned_to?(order) && service))
    actions << "check_steps" if worker && open_order
    actions << "add_note" if worker
    actions << "add_photo" if worker && order.work_order_attachments.size < WorkOrderAttachment::MAX_PER_ORDER
    actions
  end

  def charge_blocked_reason
    return nil unless @context && @order.done?
    return nil unless WorkOrders::Transition.permitted?(@order, :charge, @context)

    priced = @order.work_order_items.any? { |item| item.unit_price.to_f.positive? }
    priced ? nil : "no_items"
  end
end
