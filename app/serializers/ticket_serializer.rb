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
      voided_by: person(ticket.voided_by), void_reason: ticket.void_reason
    }
  end

  def as_json(*)
    order = @ticket.work_order
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
      work_order: {
        id:       @ticket.work_order_id,
        title:    order.title,
        priority: order.priority,
        status:   order.status,
        customer_name:  order.customer_name,
        customer_phone: order.customer_phone
      }
    }

    if @detailed
      base[:items] = order.work_order_items.map do |item|
        { description: item.description, quantity: item.quantity, unit: item.unit,
          unit_price: item.unit_price, subtotal: item.subtotal }
      end
      base[:employee] = order.employee ? { id: order.employee.id, name: order.employee.name } : nil
    end

    base
  end
end
