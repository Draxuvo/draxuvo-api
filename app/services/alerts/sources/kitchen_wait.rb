module Alerts
  module Sources
    # Comanda mandada que nadie ha empezado.
    class KitchenWait < KitchenRounds
      KIND = "kitchen_wait".freeze

      private

      def scope = CheckItem.status_new
      def since_sql = "MIN(kitchen_orders.sent_at)"
    end
  end
end
