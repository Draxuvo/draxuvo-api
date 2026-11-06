# El super admin enciende o apaga «Cobro solo por jefes» de una empresa (spec 058, FR-001 a FR-003 y FR-011). Si el valor
# no cambia no hace nada. Si cambia, en una transacción guarda el valor y el registro; al apagarlo, las ventas pasadas a
# cobro vuelven a estar en captura con su cajero y las cuentas de mesa pierden la marca «cobro pedido».
module ChargePolicy
  class Update
    def self.call(company, actor, enabled) = new(company, actor, enabled).call

    def initialize(company, actor, enabled)
      @company = company
      @actor = actor
      @enabled = enabled
    end

    def call
      return @company if @company.boss_only_charge == @enabled

      Company.transaction do
        @company.update!(boss_only_charge: @enabled)
        @company.charge_policy_changes.create!(actor: @actor, enabled: @enabled)
        release_marks unless @enabled
      end
      @company
    end

    private

    def release_marks
      now = Time.current
      @company.sales.status_open.where.not(submitted_at: nil).update_all(submitted_at: nil, updated_at: now)
      @company.checks.status_open.where.not(charge_requested_at: nil)
              .update_all(charge_requested_at: nil, charge_requested_by_id: nil, updated_at: now)
    end
  end
end
