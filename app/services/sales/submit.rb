# «Pasar a cobro» (spec 058, FR-010): con «Cobro solo por jefes», el cajero deja su venta lista para que un jefe la cobre.
# Desde ese momento el cajero ya no la edita ni la descarta. Bajo bloqueo y con el `lock_version` que vio el cajero.
module Sales
  class Submit
    include Failures

    def self.call(sale, lock_version) = new(sale, lock_version).call

    def initialize(sale, lock_version)
      @sale = sale
      @lock_version = lock_version
    end

    def call
      Sale.transaction do
        @sale.lock!
        fail!(:charge_policy_off) unless @sale.company.boss_only_charge
        ensure_open!(@sale)
        fail!(:stale_object, status: :conflict) unless @lock_version.present? && @lock_version.to_i == @sale.lock_version
        fail!(:already_submitted) if @sale.submitted_at.present?
        fail!(:nothing_to_submit) if @sale.sale_items.none?

        @sale.update!(submitted_at: Time.current)
        @sale
      end
    end
  end
end
