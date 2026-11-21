# Deja un pago integrado como «reembolso pendiente fuera de Draxuvo» (spec 069, FR-033): al anular sin reembolso o al
# marcar atendido un pago sin aplicar. No llama al proveedor. Un reembolso ya hecho no se toca.
module TerminalRefunds
  class Skip
    def self.call(charge, user:, ticket_payment: nil, reason: nil)
      refund = TerminalRefund.lock.find_by(terminal_charge_id: charge.id)
      return refund if refund&.settled?

      attrs = { status: "skipped", requested_by: user, reason: reason.to_s.strip.presence, completed_at: Time.current }
      if refund
        refund.update!(attrs.merge(ticket_payment: ticket_payment || refund.ticket_payment))
      else
        refund = TerminalRefund.create!(attrs.merge(company: charge.company, terminal_charge: charge, ticket_payment: ticket_payment,
                                                    amount: charge.amount))
      end
      TerminalEvent.log!(:refund_skipped, charge: charge, refund: refund, user: user)
      refund
    end
  end
end
