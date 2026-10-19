module Api
  module V1
    module Restaurant
      # Cobra la cuenta con uno o varios pagos. Seguro ante reintentos con Idempotency-Key (FR-021).
      class PaymentsController < BaseController
        idempotent :create

        def create
          result = ::Restaurant::AddPayment.call(find_check, restaurant_context, params)
          check = find_check
          render json: {
            payment: CheckSerializer.payment(result.payment),
            check: { status: check.status, total: CheckSerializer.money(check.total), paid: CheckSerializer.money(check.paid_total),
                     balance: CheckSerializer.money(check.balance) },
            ticket: result.close && TicketSerializer.new(result.close.ticket, detailed: true).as_json
          }, status: :created
        end
      end
    end
  end
end
