# Un jefe regresa al cajero una venta lista para cobro (spec 058, FR-010): vuelve a estar en captura y queda quién y cuándo.
module Sales
  class Return
    include Failures

    def self.call(sale, user) = new(sale, user).call

    def initialize(sale, user)
      @sale = sale
      @user = user
    end

    def call
      Sale.transaction do
        @sale.lock!
        fail!(:charge_policy_off) unless @sale.company.boss_only_charge
        ensure_open!(@sale)
        fail!(:not_submitted) if @sale.submitted_at.nil?

        @sale.update!(submitted_at: nil, returned_at: Time.current, returned_by: @user)
        @sale
      end
    end
  end
end
