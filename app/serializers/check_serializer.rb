# Cuenta con sus artículos, pagos y las acciones que `context` puede hacer ahora.
class CheckSerializer
  def self.money(value) = format("%.2f", value || 0)

  def self.person(user) = user && { id: user.id, name: user.full_name }

  def initialize(check, context:)
    @check = check
    @context = context
  end

  # Resumen para el plano de mesas.
  # `counts` ({ "ready" => 2, ... }) se puede dar ya calculado para no consultar por cada cuenta.
  # Para quien no es jefe ni dueño de la cuenta se omiten el total y el mesero (spec 032, FR-019b).
  def self.summary(check, context, counts: nil)
    counts ||= check.check_items.group(:status).count
    own = check.waiter_id == context.user.id
    summary = {
      id: check.id, opened_at: check.opened_at,
      counts: %w[new preparing ready delivered].index_with { |s| counts.fetch(s, 0) },
      mine: own,
      # Spec 058: «cobro pedido» se ve en el plano de mesas.
      charge_requested_at: check.charge_requested_at
    }
    return summary unless own || context.boss?

    summary.merge(waiter: person(check.waiter), total: money(check.total))
  end

  # Fila del filtro «Canceladas» (spec 070). Solo llega a un jefe o al mesero de la cuenta (lo recorta el listado).
  def self.cancelled_summary(check, context, cancelled_items:)
    {
      id: check.id, table: check.dining_table && { id: check.dining_table.id, name: check.dining_table.name },
      takeout_name: check.takeout_name, waiter: person(check.waiter), opened_at: check.opened_at,
      cancelled_at: check.closed_at, cancel_reason: check.cancel_reason, cancelled_by: person(check.cancelled_by),
      cancelled_items: cancelled_items, mine: check.waiter_id == context.user.id
    }
  end

  def as_json(*)
    c = @check
    {
      id: c.id, status: c.status,
      table: c.dining_table && { id: c.dining_table.id, name: c.dining_table.name },
      takeout_name: c.takeout_name, waiter: self.class.person(c.waiter), opened_at: c.opened_at,
      closed_at: c.closed_at, cancel_reason: c.cancel_reason, cancelled_by: self.class.person(c.cancelled_by),
      total: self.class.money(c.total), paid: self.class.money(c.paid_total), balance: self.class.money(c.balance),
      items: items.map { |item| item_json(item) },
      payments: c.check_payments.order(:id).map { |p| self.class.payment(p) },
      ticket_id: c.ticket&.id,
      charge_requested_at: c.charge_requested_at, charge_requested_by: self.class.person(c.charge_requested_by),
      charge_blocked_reason: Restaurant::Permissions.charge_blocked_reason(c, @context),
      allowed_actions: Restaurant::Permissions.check_actions(c, @context)
    }
  end

  def self.payment(payment)
    {
      id: payment.id, method: payment.payment_method, amount: money(payment.amount), reference: payment.reference,
      amount_received: payment.amount_received && money(payment.amount_received),
      change_given: payment.change_given && money(payment.change_given),
      terminal: PaymentTerminalSerializer.ref(payment.terminal)
    }
  end

  private

  def items
    @check.check_items.includes(:station, :kitchen_order, :check, :cancelled_by, product: :product_type).order(:id)
  end

  def item_json(item)
    {
      id: item.id, name: item.name, product_id: item.product_id, icon: item.product&.icon,
      type_icon: item.product&.product_type&.icon, quantity: item.quantity, unit_price: self.class.money(item.unit_price),
      note: item.note, status: item.status, station: item.station && { id: item.station.id, name: item.station.name },
      kitchen_order_number: item.kitchen_order&.number, sent_at: item.kitchen_order&.sent_at,
      ready_at: item.ready_at, cancel_reason: item.cancel_reason, cancelled_at: item.cancelled_at,
      cancelled_by: self.class.person(item.cancelled_by),
      allowed_actions: Restaurant::Permissions.item_actions(item, @context)
    }
  end
end
