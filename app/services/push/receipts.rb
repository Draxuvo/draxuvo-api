module Push
  # Recibos de Expo (spec 057, FR-004, research R10): Expo confirma la entrega minutos después del envío. Se piden los
  # de los avisos enviados hace entre 15 minutos y 24 horas que aún no se revisaron; un recibo `DeviceNotRegistered`
  # desactiva ese teléfono (app desinstalada o permiso retirado). Un fallo transitorio deja la revisión para la siguiente.
  class Receipts
    MIN_AGE = 15.minutes
    MAX_AGE = 24.hours
    BATCH = 500

    def self.call(now: Time.current, client: ExpoClient.new) = new(now, client).call

    def initialize(now, client)
      @now = now
      @client = client
    end

    def call
      pending.find_in_batches(batch_size: BATCH) { |deliveries| check(deliveries) }
    rescue ExpoClient::Transient => e
      Rails.logger.warn("[Push::Receipts] #{e.message}")
    end

    private

    def pending
      PushDelivery.sent.where(receipts_checked_at: nil, created_at: (@now - MAX_AGE)..(@now - MIN_AGE))
    end

    def check(deliveries)
      device_by_ticket = deliveries.flat_map(&:tickets).to_h { |ticket| [ ticket["id"], ticket["device_id"] ] }
      receipts = device_by_ticket.any? ? @client.receipts(device_by_ticket.keys) : {}

      unregistered = receipts.filter_map do |ticket_id, receipt|
        device_by_ticket[ticket_id] if receipt["status"] == "error" && receipt.dig("details", "error") == "DeviceNotRegistered"
      end
      PushDevice.active.where(id: unregistered).find_each { |device| device.disable!("not_registered") }
      PushDelivery.where(id: deliveries.map(&:id)).update_all(receipts_checked_at: @now, updated_at: @now)
    end
  end
end
