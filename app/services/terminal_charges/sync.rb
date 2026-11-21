module TerminalCharges
  # Consulta al proveedor el estado de una solicitud y la resuelve (spec 069, FR-014, FR-018 a FR-020, research R4 y R5).
  # Lo llaman el aviso del proveedor, la pantalla que espera y el barrido. La consulta va **fuera** de la transacción; la
  # resolución bloquea la fila, así que avisos repetidos, el barrido y la pantalla a la vez aplican el cobro una sola vez.
  class Sync
    # Además de las abiertas, se siguen consultando un rato las que terminaron sin cobro en Draxuvo (abandonada, vencida,
    # cancelada): si el proveedor las aprueba tarde, se aplican o quedan «sin aplicar» (SC-006).
    LATE = TerminalCharge::LATE
    WATCHED = (TerminalCharge::OPEN + LATE + %w[unapplied]).freeze

    def self.call(charge) = new(charge).call

    def initialize(charge)
      @charge = charge
    end

    def call
      return @charge unless (WATCHED.include?(@charge.status) || refund_in_flight?) && @charge.provider_order_id.present?

      remote = fetch
      return @charge unless remote

      TerminalCharge.transaction do
        @charge.lock!
        resolve(remote)
      end
      @charge
    end

    private

    def fetch
      TerminalProviders.for(@charge.terminal_connection.provider).fetch_charge(@charge)
    rescue TerminalProviders::Error => e
      TerminalConnections::Health.failed!(@charge.terminal_connection, e.failure) if e.failure.connection?
      @charge.update_columns(last_synced_at: Time.current)
      expire_overdue! if e.failure.transient? || e.failure.connection?
      raise if e.failure.transient? && !@charge.overdue?

      nil
    end

    def resolve(remote)
      @charge.update!(last_synced_at: Time.current, status_detail: remote.detail.presence || @charge.status_detail)
      return refund_update(remote) if %w[applied unapplied refunded].include?(@charge.status)

      case remote.status
      when "approved" then approve(remote)
      when "declined" then finish("declined", :charge_declined)
      when "canceled" then finish("canceled", :charge_canceled)
      when "expired" then finish("expired", :charge_expired)
      when "refunded" then approve(remote)
      else
        expire_overdue! if @charge.open?
      end
    end

    def approve(remote)
      return unless @charge.open? || LATE.include?(@charge.status)

      @charge.update!(status: "approved", provider_reference: remote.reference, card_last4: remote.card_last4,
                      payment_type: remote.payment_type, resolved_at: Time.current)
      TerminalEvent.log!(:charge_approved, charge: @charge, reference: remote.reference)
      Apply.call(@charge)
    end

    def finish(status, event)
      return unless @charge.open?

      @charge.update!(status: status, resolved_at: Time.current)
      TerminalEvent.log!(event, charge: @charge, detail: @charge.status_detail)
    end

    # Pasó su tiempo y el proveedor no la dio por vencida: se pide cancelar y queda vencida (FR-019).
    def expire_overdue!
      return unless @charge.open? && @charge.overdue?

      begin
        TerminalProviders.for(@charge.terminal_connection.provider).cancel_charge(@charge)
      rescue TerminalProviders::Error
        nil
      end
      @charge.update!(status: "expired", status_detail: "expired", resolved_at: Time.current)
      TerminalEvent.log!(:charge_expired, charge: @charge)
    end

    def refund_in_flight? = @charge.terminal_refund&.requested?

    # Un pago (aplicado o sin aplicar) con reembolso en proceso: el aviso `order.refunded` lo da por hecho.
    def refund_update(remote)
      refund = @charge.terminal_refund&.reload
      return unless refund&.requested? && (remote.status == "refunded" || remote.refund_status == "done")

      refund.complete!
    end
  end
end
