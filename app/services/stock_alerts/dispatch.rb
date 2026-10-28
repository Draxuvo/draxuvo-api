module StockAlerts
  # Aviso inmediato (spec 045, FR-011 a FR-013): cuando el producto detectado más antiguo ya espera lo suficiente
  # (StockAlertState::GRACE), manda todos los pendientes juntos en un solo mensaje por canal y persona.
  class Dispatch
    def self.call(company, now: Time.current) = new(company, now).call

    def initialize(company, now)
      @company = company
      @now = now
    end

    def call
      pending = @company.stock_alert_states.pending
      oldest = pending.minimum(:detected_at)
      return if oldest.nil? || oldest > @now - StockAlertState::GRACE

      products = Product.where(id: pending.pluck(:product_id)).order(:name)
      Notify.call(company: @company, recipients: Alerts::Recipients.call(@company), products: products,
                  kind: "immediate", sent_on: local_date)
      # Se marcan avisados aunque no haya a quién mandar: el resumen diario sigue cubriendo lo que está bajo.
      pending.update_all(notified_at: @now, updated_at: @now)
    end

    private

    def local_date = @now.in_time_zone(AlertSetting.for(@company).time_zone).to_date
  end
end
