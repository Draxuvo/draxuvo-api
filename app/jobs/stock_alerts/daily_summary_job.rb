module StockAlerts
  # Cada hora en punto (spec 045): manda el resumen a las empresas cuya hora local es la configurada.
  class DailySummaryJob < ApplicationJob
    queue_as :default

    def perform
      StockAlerts::Companies.each do |company|
        StockAlerts::DailySummary.call(company)
      rescue => e
        Rails.logger.error("[StockAlerts::DailySummaryJob] company=#{company.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
