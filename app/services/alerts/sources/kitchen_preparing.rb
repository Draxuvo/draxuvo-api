module Alerts
  module Sources
    # Comanda que ya se empezó y sigue sin terminar.
    class KitchenPreparing < KitchenRounds
      KIND = "kitchen_preparing".freeze

      private

      def scope = CheckItem.status_preparing
      def since_sql = "MIN(check_items.preparing_at)"
    end
  end
end
