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
      mine: own
    }
    return summary unless own || context.boss?

    summary.merge(waiter: person(check.waiter), total: money(check.total))
  end

  def as_json(*)
    c = @check
    {
      id: c.id, status: c.status,
      table: c.dining_table && { id: c.dining_table.id, name: c.dining_table.name },
      takeout_name: c.takeout_name, waiter: self.class.person(c.waiter), opened_at: c.opened_at,
      total: self.class.money(c.total), paid: self.class.money(c.paid_total), balance: self.class.money(c.balance),
      items: items.map { |item| item_json(item) },
      payments: c.check_payments.order(:id).map { |p| self.class.payment(p) },
      ticket_id: c.ticket&.id,
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
    @check.check_items.includes(:station, :kitchen_order, :check, product: :product_type).order(:id)
  end

  def item_json(item)
    {
      id: item.id, name: item.name, product_id: item.product_id, icon: item.product&.icon,
      type_icon: item.product&.product_type&.icon, quantity: item.quantity, unit_price: self.class.money(item.unit_price),
      note: item.note, status: item.status, station: item.station && { id: item.station.id, name: item.station.name },
      kitchen_order_number: item.kitchen_order&.number, sent_at: item.kitchen_order&.sent_at,
      ready_at: item.ready_at, allowed_actions: Restaurant::Permissions.item_actions(item, @context)
    }
  end
end
