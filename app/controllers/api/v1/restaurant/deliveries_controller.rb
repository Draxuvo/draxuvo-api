module Api
  module V1
    module Restaurant
      # El mesero entrega lo que la estación marcó listo (FR-019). Cualquier persona con sesión puede (FR-037).
      class DeliveriesController < BaseController
        def create
          check = find_check(params[:check_id])
          CheckItem.transaction do
            item = check.check_items.lock.find(params[:id])
            invalid!(:check_not_open) unless check.status_open?
            invalid!(:invalid_transition) unless item.status_ready?

            item.update!(status: :delivered, delivered_at: Time.current)
          end
          render json: serialize_check(check.reload)
        end
      end
    end
  end
end
