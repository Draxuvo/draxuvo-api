# Cuántas cosas esperan el cobro de un jefe (spec 058, FR-020): ventas pasadas a cobro, órdenes de trabajo terminadas y
# cuentas de mesa con «cobro pedido». Cada conteo solo con su módulo activo; todo en cero si la opción está apagada.
module ChargeQueue
  module_function

  def call(company)
    return { enabled: false, sales: 0, work_orders: 0, checks: 0, total: 0 } unless company.boss_only_charge

    counts = {
      sales: company.module_active?(:pos) ? company.sales.queued.count : 0,
      work_orders: company.module_active?(:work_orders) ? company.work_orders.where(status: :done).count : 0,
      checks: company.module_active?(:restaurant) ? company.checks.status_open.where.not(charge_requested_at: nil).count : 0
    }
    { enabled: true, **counts, total: counts.values.sum }
  end
end
