module Api
  module V1
    module Restaurant
      # Cierra en cero una cuenta sin nada que cobrar (cortesía completa), con motivo (FR-024).
      class CheckClosuresController < BaseController
        before_action :require_boss!

        def create
          check = find_check
          reason = params[:reason].to_s.strip
          invalid!(:reason_required) if reason.empty?

          ticket = Check.transaction do
            check.lock!
            invalid!(:check_not_open) unless check.status_open?
            invalid!(:not_zero_total) unless check.total.zero? && check.check_items.counted.none?

            check.check_items.status_draft.destroy_all
            ::Restaurant::CloseCheck.call(check, current_user, reason: reason).ticket
          end
          render json: { check: serialize_check(check.reload), ticket: TicketSerializer.new(ticket, detailed: true).as_json }, status: :created
        end
      end
    end
  end
end
