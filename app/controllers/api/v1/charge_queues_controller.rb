# Cola «Por cobrar» del panel (spec 058, FR-020): solo dueño, administrador y super admin. El panel la sondea cada 30 s.
module Api
  module V1
    class ChargeQueuesController < BaseController
      before_action :require_boss!

      # GET /api/v1/charge_queue
      def show
        render json: ::ChargeQueue.call(current_company)
      end
    end
  end
end
