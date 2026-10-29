module StockAlerts
  # Manda el aviso de stock bajo por correo a cada destinatario y deja un registro por envío (spec 045, FR-011, FR-014
  # y FR-015). Desde la spec 048 el único canal es el correo (WhatsApp ya no se usa; los registros anteriores con canal
  # `whatsapp` se conservan). Un fallo de una persona no detiene a las demás. El resumen diario no se repite el mismo
  # día: el índice único de `alert_deliveries` lo impide y ese envío se omite.
  class Notify
    def self.call(**args) = new(**args).call

    def initialize(company:, recipients:, products:, kind:, sent_on:)
      @company = company
      @recipients = recipients
      @products = products.to_a
      @kind = kind
      @sent_on = sent_on
    end

    def call
      return if @products.empty?

      @recipients.each do |recipient|
        deliver(recipient, "email") { email(recipient.user) } if recipient.email
      end
    end

    private

    def deliver(recipient, channel)
      return if @kind == "daily" && already_sent_today?(recipient.user, channel)

      status, error = yield
      record(recipient.user, channel, status, error)
    rescue ActiveRecord::RecordNotUnique
      nil # el resumen de hoy ya se mandó por este canal
    rescue => e
      Rails.logger.error("[StockAlerts::Notify] #{channel} user=#{recipient.user.id}: #{e.class}: #{e.message}")
      record(recipient.user, channel, "failed", e.message.to_s.truncate(200))
    end

    # Se mira antes de mandar: el índice único solo evitaría el registro, no el mensaje repetido.
    def already_sent_today?(user, channel)
      AlertDelivery.exists?(company_id: @company.id, user_id: user.id, channel: channel, kind: "daily", sent_on: @sent_on)
    end

    def email(user)
      return [ "simulated" ] if @company.demo?

      response = ResendMailer.stock_alert(user: user, company_name: @company.name, kind: @kind, products: @products)
      return [ "failed", "email" ] unless response

      [ response["id"] == "demo-simulated" ? "simulated" : "sent" ]
    end

    def record(user, channel, status, error)
      AlertDelivery.create!(company: @company, user: user, channel: channel, kind: @kind, status: status, error: error,
                            product_ids: @products.map(&:id), sent_on: @sent_on)
    end
  end
end
