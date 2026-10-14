# app/controllers/api/v1/tickets_controller.rb
module Api
  module V1
    class TicketsController < BaseController
      requires_module :tickets
      requires_module :whatsapp, only: :send_whatsapp

      def index
        tickets = current_company.tickets
                                 .includes(work_order: :work_order_items)

        tickets = tickets.where(status: params[:status]) if params[:status].present?
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

      def mark_as_paid
        ticket = find_ticket
        raise ApiErrors::BadRequestError.new(details: I18n.t("ticket.already_paid")) if ticket.paid?

        ticket.update!(status: :paid, paid_at: Time.current)
        render json: TicketSerializer.new(ticket).as_json
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
        phone  = params.require(:phone)

        Whatsapp::TicketService.new(ticket, phone: phone).call
        render json: { message: I18n.t("ticket.whatsapp_sent") }
      rescue ActionController::ParameterMissing
        raise ApiErrors::BadRequestError.new(details: "El parámetro 'phone' es requerido")
      end

      private

      def find_ticket
        current_company.tickets.includes(work_order: :work_order_items).find(params[:id])
      end
    end
  end
end
