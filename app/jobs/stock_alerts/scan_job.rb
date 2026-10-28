module StockAlerts
  # Cada 5 minutos (spec 045): detecta los productos que acaban de bajar y manda el aviso inmediato agrupado.
  class ScanJob < ApplicationJob
    queue_as :default

    def perform
      StockAlerts::Companies.each do |company|
        StockAlerts::Scan.call(company)
        StockAlerts::Dispatch.call(company)
      rescue => e
        # Una empresa con problemas no detiene al resto.
        Rails.logger.error("[StockAlerts::ScanJob] company=#{company.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
