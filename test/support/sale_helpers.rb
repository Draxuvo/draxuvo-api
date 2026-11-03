# Ayudantes de las pruebas del punto de venta (spec 050).
module SaleHelpers
  # Venta abierta de la papelería con los renglones indicados: [[producto, cantidad], ...].
  def open_sale(user = users(:pos_staff), *lines, company: companies(:pos_co))
    sale = Sale.create!(company: company, opened_by: user)
    lines.each { |product, quantity| Sales::AddItem.call(sale, product_id: product.id, quantity: quantity) }
    sale.reload
  end

  # Cobra una venta en efectivo por el total (o por `received`).
  def charge_cash(sale, user = users(:pos_staff), received: nil)
    Sales::Charge.call(sale, user, lock_version: sale.reload.lock_version,
                                   payments: [ { method: "cash", amount_received: (received || sale.total).to_s } ])
  end
end

ActiveSupport::TestCase.include SaleHelpers
