module Push
  # Avisa «orden asignada» (spec 057, US3). Reintenta hasta 3 veces si Expo falla y luego lo registra como fallido.
  class WorkOrderAssignedJob < ApplicationJob
    queue_as :default

    ATTEMPTS = 3

    retry_on ExpoClient::Transient, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      order = WorkOrder.includes(employee: :user).find_by(id: job.arguments.first)
      user = order&.employee&.user
      if user
        Deliver.record(company: order.company, user: user, kind: WorkOrderAssigned::KIND, subject_key: "work_order:#{order.id}",
                       status: "failed", error: error.message, attempts: ATTEMPTS)
      end
    end

    def perform(work_order_id, employee_id, actor_id = nil)
      WorkOrderAssigned.call(work_order_id: work_order_id, employee_id: employee_id, actor_id: actor_id, attempt: executions)
    end
  end
end
