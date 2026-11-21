# Pide al proveedor el reembolso total de un pago integrado (spec 069, FR-031, FR-033, FR-036, research R8).
#
# La fila `terminal_refunds` se crea (o se reutiliza) bajo bloqueo **antes** de llamar, y la llamada va fuera de toda
# transacción. La llave de idempotencia se reutiliza mientras el reembolso está `requested` (también si la llamada anterior
# no tuvo respuesta), así un reintento nunca devuelve dos veces; solo un rechazo confirmado abre un intento nuevo con otra
# llave. Si el proveedor no lo acepta, responde 422 `refund_failed` con el motivo y quien llama no anula nada.
module TerminalRefunds
  class Request
    # Motivos del proveedor que se muestran tal cual; los demás se agrupan en `refund_rejected`.
    KNOWN_REASONS = %w[refund_period_exceeded insufficient_money_for_refund].freeze

    def self.call(charge, user:, ticket_payment: nil, reason: nil)
      new(charge, user: user, ticket_payment: ticket_payment, reason: reason).call
    end

    def initialize(charge, user:, ticket_payment:, reason:)
      @charge = charge
      @user = user
      @ticket_payment = ticket_payment
      @reason = reason.to_s.strip.presence
    end

    def call
      connection = @charge.terminal_connection
      fail!("connection_error") unless connection&.connected?

      refund = reserve
      begin
        result = TerminalProviders.for(connection.provider).refund(@charge, idempotency_key: refund.idempotency_key)
      rescue TerminalProviders::Error => e
        rejected!(refund, e.failure)
      end
      result.status == "done" ? refund.complete!(provider_refund_id: result.id) : refund.update!(provider_refund_id: result.id)
      refund
    end

    private

    def reserve
      TerminalCharge.transaction do
        @charge.lock!
        refund = TerminalRefund.lock.find_by(terminal_charge_id: @charge.id)
        TerminalCharges::Errors.conflict!(:already_refunded) if refund&.settled?

        if refund.nil?
          refund = TerminalRefund.create!(company: @charge.company, terminal_charge: @charge, ticket_payment: @ticket_payment,
                                          amount: @charge.amount, status: "requested", reason: @reason, requested_by: @user)
        else
          refund.next_attempt! if refund.rejected?
          refund.update!(requested_by: @user, reason: @reason || refund.reason, ticket_payment: @ticket_payment || refund.ticket_payment)
        end
        TerminalEvent.log!(:refund_requested, charge: @charge, refund: refund, user: @user, attempt: refund.attempts,
                                              amount: refund.amount.to_s)
        refund
      end
    end

    # Sin respuesta (caído o tiempo agotado) el resultado es incierto: queda `requested` y el siguiente intento reutiliza la
    # llave (el barrido también lo consulta). Un rechazo explícito queda `rejected` y abre un intento nuevo.
    def rejected!(refund, failure)
      code = reason_for(failure)
      TerminalConnections::Health.failed!(@charge.terminal_connection, failure) if failure.connection?
      unless failure.transient?
        refund.update!(status: "rejected", error_code: code, error_message: failure.reason.to_s.first(200))
        TerminalEvent.log!(:refund_rejected, charge: @charge, refund: refund, user: @user, reason: code)
      end
      fail!(code)
    end

    def reason_for(failure)
      return "connection_error" if failure.connection?
      return "provider_unavailable" if failure.transient?

      KNOWN_REASONS.include?(failure.reason.to_s) ? failure.reason.to_s : "refund_rejected"
    end

    def fail!(code)
      message = I18n.t("terminal_charge.refund_reasons.#{code}", default: I18n.t("terminal_charge.errors.refund_failed"))
      raise ApiErrors::UnprocessableEntityError.new(
        message: message, details: { code: "refund_failed", reason: code, ticket_payment_id: @ticket_payment&.id }
      )
    end
  end
end
