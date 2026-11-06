module Api
  module V1
    module Restaurant
      # «Pedir cobro» de una cuenta (spec 058, FR-023): el mesero de la cuenta o un jefe, con «Cobro solo por jefes».
      # Avisa a los jefes con el push «Por cobrar».
      class ChargeRequestsController < BaseController
        # POST /api/v1/restaurant/checks/:id/charge_request
        def create
          check = find_check
          already = check.charge_requested_at.present?
          ::Restaurant::RequestCharge.call(check, restaurant_context)
          ::Push::ChargePendingJob.perform_later("check", check.id, current_user.id) unless already
          render json: serialize_check(find_check)
        end
      end
    end
  end
end
