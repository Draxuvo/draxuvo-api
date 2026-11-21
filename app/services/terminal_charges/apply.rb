module TerminalCharges
  # Registra el cobro aprobado con los servicios de siempre (spec 069, FR-014, FR-020, research R6). Se llama dentro de
  # la transacción de `Sync`, con la solicitud bloqueada y en `approved`, así que corre una sola vez. Si el cobro ya no
  # se puede aplicar (cobrado por otra vía, venta cambiada, saldo menor, regla de cobro), la solicitud queda «sin aplicar»
  # para que un jefe la reembolse; nunca se registra un segundo cobro.
  class Apply
    def self.call(charge) = new(charge).call

    def initialize(charge)
      @charge = charge
    end

    def call
      return @charge unless @charge.status == "approved"

      @late = @charge.status_previously_was.in?(Sync::LATE)
      owner = Owner.for_charge(@charge)
      payment, result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        payment, result = owner.apply!(@charge.params.with_indifferent_access, terminal_payment)
      end
      link!(payment, result)
    rescue ApiErrors::BaseError => e
      unapplied!(error_code(e))
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      unapplied!(e.is_a?(ActiveRecord::RecordNotFound) ? "not_found" : "invalid")
    end

    private

    def terminal_payment
      { amount: @charge.amount, terminal: @charge.payment_terminal, terminal_charge: @charge,
        reference: @charge.provider_reference, card_last4: @charge.card_last4 }
    end

    def link!(payment, result)
      attrs = { status: "applied", applied_at: Time.current, params: @charge.params.merge("result" => result.as_json) }
      attrs[payment.is_a?(CheckPayment) ? :check_payment_id : :ticket_payment_id] = payment&.id
      @charge.update!(attrs)
      TerminalEvent.log!(:charge_applied, charge: @charge, payment_id: payment&.id)
      @charge
    end

    # Una aprobación tardía que ya no cabe casi siempre es porque se cobró por otra vía (registro a mano).
    def unapplied!(reason)
      reason = "already_paid" if @late && %w[invalid sale_not_open check_not_open exceeds_balance invalid_amount].include?(reason.to_s)
      @charge.update!(status: "unapplied", unapplied_reason: reason.to_s.first(60))
      TerminalEvent.log!(:charge_unapplied, charge: @charge, reason: reason.to_s)
      @charge
    end

    def error_code(error)
      details = error.details
      code = details.is_a?(Hash) ? (details[:code] || details["code"]) : nil
      code.presence || (error.status.to_s == "forbidden" ? "forbidden" : "invalid")
    end
  end
end
