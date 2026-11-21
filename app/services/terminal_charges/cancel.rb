module TerminalCharges
  # Cancela una solicitud pendiente (spec 069, FR-015, US1 escenario 3). La llamada al proveedor va fuera de transacción:
  # recién creada se cancela al instante; ya en la terminal queda «cancelando» hasta el aviso; si el proveedor ya la está
  # cobrando responde 409 `not_cancelable`.
  class Cancel
    def self.call(charge, user:) = new(charge, user).call

    def initialize(charge, user)
      @charge = charge
      @user = user
    end

    def call
      Errors.conflict!(:not_cancelable, status: @charge.status) unless @charge.pending?

      outcome = TerminalProviders.for(@charge.terminal_connection.provider).cancel_charge(@charge)
      TerminalCharge.transaction do
        @charge.lock!
        break unless @charge.pending?

        case outcome
        when :canceled
          @charge.update!(status: "canceled", status_detail: "canceled_by_api", resolved_at: Time.current, cancel_requested_at: Time.current)
          TerminalEvent.log!(:charge_canceled, charge: @charge, user: @user)
        when :requested
          @charge.update!(status: "canceling", status_detail: "cancellation_requested", cancel_requested_at: Time.current)
        else
          Errors.conflict!(:not_cancelable, status: @charge.status)
        end
      end
      @charge
    rescue TerminalProviders::Error => e
      TerminalConnections::Health.failed!(@charge.terminal_connection, e.failure) if e.failure.connection?
      Errors.bad_gateway!(:provider_unavailable)
    end
  end
end
