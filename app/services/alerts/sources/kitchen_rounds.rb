module Alerts
  module Sources
    # Comandas (los artículos de una estación mandados en una misma tanda) que llevan demasiado en un mismo estado.
    # Una comanda con varios platillos de cocina es una sola alerta. El límite depende del tipo de estación.
    # Las subclases (KitchenWait, KitchenPreparing) dicen qué artículos miran (`scope`) y desde cuándo (`since_sql`).
    class KitchenRounds < Base
      def self.module_key = :restaurant

      def call
        rows = grouped_rows
        return [] if rows.empty?

        orders = KitchenOrder.where(id: rows.map(&:first)).includes(check: :dining_table).index_by(&:id)
        stations = Station.where(id: rows.filter_map { |row| row[1] }).index_by(&:id)
        rows.filter_map { |order_id, station_id, since| build(orders.fetch(order_id), stations[station_id], station_id, since) }
      end

      private

      def grouped_rows
        scope.where(company_id: company.id).where.not(kitchen_order_id: nil)
             .joins(:kitchen_order, :check).merge(Check.status_open)
             .group(:kitchen_order_id, :station_id)
             .pluck(:kitchen_order_id, :station_id, Arel.sql(since_sql))
      end

      def build(order, station, station_id, since)
        limit = thresholds.minutes(self.class::KIND, station&.kind)
        return unless over?(since, limit)

        minutes = elapsed_minutes(since)
        Alert.new(
          kind: self.class::KIND, subject_key: "ko:#{order.id}:st:#{station_id || 0}",
          severity: severity_for(minutes, limit), minutes: minutes, threshold_minutes: limit,
          subject: { type: "kitchen_order", id: order.id, label: label(order, station), check_id: order.check_id },
          owner: station && { type: "station", name: station.name }
        )
      end

      def label(order, station)
        check = order.check
        where = check.takeout? ? I18n.t("alerts.labels.takeout", name: check.takeout_name) : I18n.t("alerts.labels.table", name: check.dining_table.name)
        return I18n.t("alerts.labels.round_no_station", where: where, number: order.number) unless station

        I18n.t("alerts.labels.round", where: where, number: order.number, station: station.name)
      end
    end
  end
end
