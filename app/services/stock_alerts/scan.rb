module StockAlerts
  # Detecta los productos que acaban de bajar a su mínimo y rearma los que ya se repusieron (spec 045, research R3).
  # No manda nada: solo deja el estado que `Dispatch` usa para avisar.
  class Scan
    def self.call(company, now: Time.current) = new(company, now).call

    def initialize(company, now)
      @company = company
      @now = now
    end

    def call
      low_ids = Product.where(company_id: @company.id).low_stock.pluck(:id)
      known = @company.stock_alert_states.pluck(:product_id)

      # Ya no está bajo: se borra su estado y, si vuelve a bajar, se avisa otra vez (FR-013).
      @company.stock_alert_states.where.not(product_id: low_ids).delete_all

      fresh = low_ids - known
      return if fresh.empty?

      rows = fresh.map { |id| { company_id: @company.id, product_id: id, detected_at: @now, created_at: @now, updated_at: @now } }
      StockAlertState.insert_all(rows, unique_by: :product_id)
    end
  end
end
