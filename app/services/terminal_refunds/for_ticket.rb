# Reembolsos de los pagos integrados al anular el cobro de una orden de trabajo o cancelar una venta (spec 069, FR-031 a
# FR-033, contracts/api.md «Anulaciones con reembolso»). Se llama **antes** de la transacción de la anulación:
#
# - sin pagos integrados activos (o ya reembolsados): no hace nada y `refund` se ignora;
# - sin `refund`: 422 `refund_confirmation_required` con lo que se devolvería, para que la pantalla lo confirme;
# - `confirm`: pide cada reembolso; si alguno falla responde 422 `refund_failed` y la anulación no ocurre;
# - `skip`: la anulación sigue y `settle!` (ya dentro de su transacción) deja cada pago «pendiente fuera de Draxuvo».
module TerminalRefunds
  class ForTicket
    def self.call(ticket, user:, mode:, reason:) = new(ticket, user: user, mode: mode, reason: reason).call

    def initialize(ticket, user:, mode:, reason:)
      @ticket = ticket
      @user = user
      @mode = mode.to_s
      @reason = reason
    end

    def call
      return self if pending.empty?

      case @mode
      when "confirm"
        pending.each do |payment|
          Request.call(payment.terminal_charge, user: @user, ticket_payment: payment, reason: @reason)
        end
      when "skip" then nil
      else confirmation_required!
      end
      self
    end

    # Dentro de la transacción de la anulación.
    def settle!
      return unless @mode == "skip"

      pending.each { |payment| Skip.call(payment.terminal_charge, user: @user, ticket_payment: payment, reason: @reason) }
    end

    private

    def pending
      @pending ||= @ticket.ticket_payments.active.where(source: :terminal)
                          .includes(terminal_charge: %i[terminal_refund payment_terminal]).to_a
                          .reject { |payment| payment.terminal_charge.terminal_refund&.settled? }
    end

    def confirmation_required!
      refunds = pending.map do |payment|
        { ticket_payment_id: payment.id, amount: format("%.2f", payment.amount),
          terminal: PaymentTerminalSerializer.ref(payment.terminal_charge.payment_terminal) }
      end
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("terminal_charge.errors.refund_confirmation_required"),
        details: { code: "refund_confirmation_required", refunds: refunds }
      )
    end
  end
end
