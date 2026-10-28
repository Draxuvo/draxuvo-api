module StockAlerts
  # Resumen diario (spec 045, FR-013a): a la hora local configurada de la empresa manda todos los productos que siguen
  # en o bajo su mínimo, por los mismos canales y a los mismos destinatarios que el aviso inmediato. Sin productos
  # bajos no manda nada. Corre cada hora; el índice único de `alert_deliveries` evita repetir el del día.
  class DailySummary
    def self.call(company, now: Time.current) = new(company, now).call

    def initialize(company, now)
      @company = company
      @now = now
      @setting = AlertSetting.for(company)
    end

    def call
      local = @now.in_time_zone(@setting.time_zone)
      return unless local.hour == @setting.summary_hour

      products = Product.where(company_id: @company.id).low_stock.order(:name)
      return if products.none?

      Notify.call(company: @company, recipients: Alerts::Recipients.call(@company), products: products,
                  kind: "daily", sent_on: local.to_date)
    end
  end
end
