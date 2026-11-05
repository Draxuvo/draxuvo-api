module Push
  # Recibos de Expo cada 15 minutos (spec 057, `config/recurring.yml`).
  class ReceiptsJob < ApplicationJob
    queue_as :default

    def perform = Receipts.call
  end
end
