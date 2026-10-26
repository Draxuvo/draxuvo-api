# app/controllers/api/v1/tickets_controller.rb
module Api
  module V1
    class TicketsController < BaseController
      requires_module :tickets
      requires_module :whatsapp, only: :send_whatsapp

      def index
        tickets = base_scope.includes(:check, work_order: :work_order_items)

        tickets = tickets.where(status: params[:status]) if Ticket.statuses.key?(params[:status])
        tickets = search_tickets(tickets, params[:search])  if params[:search].present?
        tickets = apply_sort(tickets,
                    allowed: %i[folio status total created_at paid_at],
                    default: :created_at, default_dir: :desc)

        @pagy, tickets = pagy(tickets)
        render json: paginate_response(@pagy, tickets.map { |t| TicketSerializer.new(t).as_json })
      end

      def show
        ticket = find_ticket
        render json: TicketSerializer.new(ticket, detailed: true).as_json
      end

      def download
        ticket = find_ticket
        pdf    = Pdf::TicketPdfService.new(ticket).generate
        send_data pdf,
                  filename:    "ticket-#{ticket.folio}.pdf",
                  type:        "application/pdf",
                  disposition: "attachment"
      end

      def send_whatsapp
        ticket = find_ticket
        phone  = params[:phone].presence || ticket.work_order&.customer_phone.presence
        raise ApiErrors::BadRequestError.new(details: I18n.t("ticket.phone_required")) if phone.blank?

        Whatsapp::TicketService.new(ticket, phone: phone).call
        body = { message: I18n.t("ticket.whatsapp_sent") }
        body[:demo] = true if Demo::Guard.active?
        render json: body
      end

      private

      def search_tickets(tickets, query)
        term = "%#{Ticket.sanitize_sql_like(query)}%"
        tickets.left_joins(:work_order, check: :dining_table)
               .where("tickets.folio ILIKE :term OR work_orders.title ILIKE :term OR work_orders.customer_name ILIKE :term " \
                      "OR checks.takeout_name ILIKE :term OR dining_tables.name ILIKE :term", term: term)
      end

      def find_ticket
        base_scope.includes(:check, work_order: :work_order_items).find(params[:id])
      end

      # Staff solo ve los tickets de sus órdenes y de sus cuentas de restaurante.
      def base_scope
        scope = current_company.tickets
        return scope unless current_role == "staff"

        scope.left_joins(:work_order, :check)
             .where("work_orders.employee_id = :employee OR checks.waiter_id = :user",
                    employee: current_employee&.id, user: current_user.id)
      end
    end
  end
end
