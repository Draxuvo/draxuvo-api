module Reports
  class IncomeService
    def initialize(company, range, group_by)
      @company  = company
      @range    = range
      @group_by = group_by
    end

    def call
      tickets = @company.tickets.where(status: :paid, paid_at: @range).order(:paid_at)

      {
        period:        { from: @range.first, to: @range.last },
        total_revenue: tickets.sum(:total).to_f,
        total_tickets: tickets.count,
        by_period:     group_tickets(tickets),
        breakdown:     breakdown(tickets),
        by_method:     by_method(tickets),
        by_terminal:   by_terminal(tickets)
      }
    end

    private

    # Pagos que cuentan como ingreso (spec 015, R11): los no anulados de órdenes y los de cuentas, de los
    # tickets pagados del rango. Cada uno como [método, terminal, monto].
    def payments(tickets)
      @payments ||= begin
        ids = tickets.select(:id)
        order_payments = TicketPayment.active.where(ticket_id: ids).includes(:terminal)
        check_payments = CheckPayment.joins(check: :ticket).where(tickets: { id: ids }).includes(:terminal)
        (order_payments.to_a + check_payments.to_a).map { |p| [ p.payment_method, p.terminal, p.amount ] }
      end
    end

    def by_method(tickets)
      payments(tickets).group_by(&:first).map do |method, group|
        { method: method, label: I18n.t("ticket.payment_method.#{method}"), total: group.sum { |p| p.last.to_f }, count: group.size }
      end.sort_by { |row| -row[:total] }
    end

    # Solo tarjeta, con un renglón `terminal: nil` para lo cobrado sin elegir terminal.
    def by_terminal(tickets)
      payments(tickets).select { |method, _, _| method == "card" }.group_by { |p| p[1] }.map do |terminal, group|
        { terminal: PaymentTerminalSerializer.ref(terminal), total: group.sum { |p| p.last.to_f }, count: group.size }
      end.sort_by { |row| -row[:total] }
    end

    def group_tickets(tickets)
      tickets.group_by { |t| Reports::PeriodKey.call(t.paid_at, @group_by) }.map do |period, group|
        {
          period:  period,
          revenue: group.sum { |t| t.total.to_f },
          count:   group.size
        }
      end.sort_by { |g| g[:period] }
    end

    def breakdown(tickets)
      tickets.includes({ work_order: :employee }, { check: %i[dining_table waiter] }).map do |ticket|
        {
          id:         ticket.id,
          folio:      ticket.folio,
          total:      ticket.total.to_f,
          paid_at:    ticket.paid_at,
          work_order: breakdown_source(ticket)
        }
      end
    end

    # Una orden de trabajo, o una cuenta de restaurante con su mesa y su mesero en los mismos campos.
    def breakdown_source(ticket)
      order = ticket.work_order
      return { id: ticket.work_order_id, title: order.title, employee: order.employee&.name } if order

      check = ticket.check
      title = check.dining_table ? "Mesa #{check.dining_table.name}" : "Para llevar: #{check.takeout_name}"
      { id: nil, title: title, employee: check.waiter.full_name }
    end
  end
end
