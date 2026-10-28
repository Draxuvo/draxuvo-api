module Alerts
  module Sources
    # Cuentas de mesa abiertas más tiempo del permitido (spec 045). Las cuentas para llevar no cuentan: la spec habla de mesas.
    class TableOpen < Base
      KIND = "table_open".freeze

      def self.module_key = :restaurant

      def call
        limit = thresholds.minutes(KIND)
        Check.status_open.where(company_id: company.id).where.not(dining_table_id: nil)
             .where(opened_at: ...(now - (limit * 60))).includes(:dining_table, :waiter)
             .map { |check| build(check, limit) }
      end

      private

      def build(check, limit)
        minutes = elapsed_minutes(check.opened_at)
        Alert.new(
          kind: KIND, subject_key: "check:#{check.id}:t:#{check.opened_at.to_i}", severity: severity_for(minutes, limit),
          minutes: minutes, threshold_minutes: limit,
          subject: { type: "check", id: check.id, label: I18n.t("alerts.labels.table", name: check.dining_table.name), check_id: check.id },
          owner: { type: "waiter", name: check.waiter.full_name }, total: format("%.2f", check.total)
        )
      end
    end
  end
end
