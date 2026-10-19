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
        breakdown:     breakdown(tickets)
      }
    end

    private

    def group_tickets(tickets)
      tickets.group_by { |t| period_key(t.paid_at) }.map do |period, group|
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

    def period_key(datetime)
      case @group_by
      when "week"  then datetime.strftime("%Y-W%V")
      when "year"  then datetime.strftime("%Y")
      else              datetime.strftime("%Y-%m")
      end
    end
  end
end
