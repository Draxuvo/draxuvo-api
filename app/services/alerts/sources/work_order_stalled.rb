module Alerts
  module Sources
    # Órdenes de trabajo abiertas (desde su creación) o en curso (desde que se empezaron) que no avanzan.
    class WorkOrderStalled < Base
      KIND = "work_order_stalled".freeze

      def self.module_key = :work_orders

      def call
        limit = thresholds.minutes(KIND)
        cutoff = now - (limit * 60)
        scope = WorkOrder.where(company_id: company.id).includes(:employee)
        stalled = scope.where(status: :open).where(created_at: ...cutoff) +
                  scope.where(status: :in_progress).where("COALESCE(work_orders.started_at, work_orders.created_at) < ?", cutoff)
        stalled.map { |order| build(order, limit) }
      end

      private

      def build(order, limit)
        since = order.in_progress? ? (order.started_at || order.created_at) : order.created_at
        minutes = elapsed_minutes(since)
        Alert.new(
          kind: KIND, subject_key: "wo:#{order.id}:t:#{since.to_i}", severity: severity_for(minutes, limit),
          minutes: minutes, threshold_minutes: limit,
          subject: { type: "work_order", id: order.id, label: I18n.t("alerts.labels.work_order", id: order.id, title: order.title) },
          owner: order.employee && { type: "employee", name: order.employee.name }
        )
      end
    end
  end
end
