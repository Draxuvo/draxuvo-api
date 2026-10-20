# app/serializers/ticket_serializer.rb
class TicketSerializer
  def initialize(ticket, detailed: false)
    @ticket   = ticket
    @detailed = detailed
  end

  # { id, name } de la persona (User o Employee) que aparece en una acción.
  def self.person(record)
    return nil unless record

    { id: record.id, name: record.respond_to?(:full_name) ? record.full_name : record.name }
  end

  # Ticket anidado en la orden: el cobro completo sin repetir la orden.
  def self.person_ticket(ticket)
    {
      id: ticket.id, folio: ticket.folio, status: ticket.status,
      payment_method: ticket.payment_method, amount_received: ticket.amount_received,
      change_given: ticket.change_given, total: ticket.total, paid_at: ticket.paid_at,
      charged_by: person(ticket.charged_by), voided_at: ticket.voided_at,
      voided_by: person(ticket.voided_by), void_reason: ticket.void_reason,
      payments: ticket.ticket_payments.map { |payment| payment_json(payment) }
    }
  end

  # Un pago del cobro de una orden (spec 015); los anulados traen `voided_at`.
  def self.payment_json(payment)
    CheckSerializer.payment(payment).merge(
      method_label: I18n.t("ticket.payment_method.#{payment.payment_method}"),
      authorization_code: payment.authorization_code, card_last4: payment.card_last4, source: payment.source,
      created_by: person(payment.created_by), created_at: payment.created_at, voided_at: payment.voided_at
    )
  end

  def as_json(*)
    order = @ticket.work_order
    check = @ticket.check
    base = {
      id:           @ticket.id,
      folio:        @ticket.folio,
      status:       @ticket.status,
      status_label: I18n.t("ticket.status.#{@ticket.status}"),
      total:        @ticket.total,
      notes:        @ticket.notes,
      paid_at:      @ticket.paid_at,
      created_at:   @ticket.created_at,
      payment_method: @ticket.payment_method,
      payment_method_label: @ticket.payment_method && I18n.t("ticket.payment_method.#{@ticket.payment_method}"),
      amount_received: @ticket.amount_received,
      change_given: @ticket.change_given,
      charged_by:   self.class.person(@ticket.charged_by),
      voided_at:    @ticket.voided_at,
      voided_by:    self.class.person(@ticket.voided_by),
      void_reason:  @ticket.void_reason,
      work_order: order && {
        id:       @ticket.work_order_id,
        title:    order.title,
        priority: order.priority,
        status:   order.status,
        customer_name:  order.customer_name,
        customer_phone: order.customer_phone
      },
      check: check && check_json(check)
    }

    base.merge!(detail(order, check)) if @detailed

    base
  end

  private

  def check_json(check)
    { id: check.id, table: check.dining_table&.name, takeout_name: check.takeout_name, waiter: self.class.person(check.waiter) }
  end

  def detail(order, check)
    return check_detail(check) unless order

    {
      items: order.work_order_items.map do |item|
        { description: item.description, quantity: item.quantity, unit: item.unit,
          unit_price: item.unit_price, subtotal: item.subtotal }
      end,
      employee: order.employee ? { id: order.employee.id, name: order.employee.name } : nil,
      payments: @ticket.ticket_payments.map { |payment| self.class.payment_json(payment) }
    }
  end

  # Ticket de una cuenta de restaurante: lo cobrado (sin cancelados) y cada pago con su método.
  def check_detail(check)
    {
      items: check.check_items.counted.order(:id).map do |item|
        { description: item.name, quantity: item.quantity, unit: nil, unit_price: item.unit_price, subtotal: item.subtotal }
      end,
      payments: check.check_payments.order(:id).map { |payment| CheckSerializer.payment(payment) },
      employee: nil
    }
  end
end
