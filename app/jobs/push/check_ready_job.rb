module Push
  # Avisa «comanda lista» (spec 057, US1). Se encola con unos segundos de espera para agrupar los artículos de la comanda
  # que la estación marca casi a la vez; si hace falta esperar al minuto entre avisos (FR-024), se reencola. Ante un
  # fallo transitorio de Expo reintenta hasta 3 veces (FR-022); un aviso que ya venció lo registra `CheckReady`.
  class CheckReadyJob < ApplicationJob
    queue_as :default

    WINDOW = 6.seconds
    ATTEMPTS = 3

    retry_on ExpoClient::Transient, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      kitchen_order = KitchenOrder.includes(:check).find_by(id: job.arguments.first)
      if kitchen_order
        Deliver.record(company: kitchen_order.check.company, user: kitchen_order.check.waiter, kind: CheckReady::KIND,
                       subject_key: "kitchen_order:#{kitchen_order.id}", status: "failed", error: error.message,
                       attempts: ATTEMPTS)
      end
    end

    def self.enqueue_for(kitchen_order_ids, actor_id)
      Array(kitchen_order_ids).compact.uniq.each { |id| set(wait: WINDOW).perform_later(id, actor_id) }
    end

    def perform(kitchen_order_id, actor_id = nil)
      result = CheckReady.call(kitchen_order_id: kitchen_order_id, actor_id: actor_id, attempt: executions)
      self.class.set(wait_until: result.retry_at).perform_later(kitchen_order_id, actor_id) if result.status == :retry
    end
  end
end
