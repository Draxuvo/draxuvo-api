module TerminalCharges
  # Respaldo manual (spec 069, US3, FR-023, FR-024, research R7): intenta cancelar en el proveedor y, responda o no, deja la
  # solicitud `abandoned` para que el cajero registre el pago a mano. Si el proveedor la aprueba después, `Sync` la deja
  # «sin aplicar» en vez de cobrar dos veces.
  class Abandon
    def self.call(charge, user:) = new(charge, user).call

    def initialize(charge, user)
      @charge = charge
      @user = user
    end

    def call
      Errors.invalid!(:not_abandonable) unless @charge.open?

      begin
        TerminalProviders.for(@charge.terminal_connection.provider).cancel_charge(@charge) if @charge.provider_order_id.present?
      rescue TerminalProviders::Error => e
        TerminalConnections::Health.failed!(@charge.terminal_connection, e.failure) if e.failure.connection?
      end

      TerminalCharge.transaction do
        @charge.lock!
        Errors.invalid!(:not_abandonable) unless @charge.open?

        @charge.update!(status: "abandoned", resolved_at: Time.current)
        TerminalEvent.log!(:charge_abandoned, charge: @charge, user: @user)
      end
      @charge
    end
  end
end
