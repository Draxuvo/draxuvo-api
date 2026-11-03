require "test_helper"

class Sales::ChargeTest < ActiveSupport::TestCase
  setup do
    @cashier = users(:pos_staff)
    @sale = open_sale(@cashier, [ products(:pos_cuaderno), 2 ])
  end

  def charge(payments, sale: @sale, lock_version: nil)
    Sales::Charge.call(sale, @cashier, lock_version: lock_version || sale.reload.lock_version, payments: payments)
  end

  test "cash with change creates the paid ticket, the payment and marks the sale paid" do
    result = charge([ { method: "cash", amount_received: "100" } ])

    assert result.sale.status_paid?
    assert_equal @cashier, result.sale.charged_by
    assert_not_nil result.sale.paid_at
    ticket = result.ticket
    assert ticket.paid?
    assert_equal @sale, ticket.sale
    assert_equal BigDecimal("85.00"), ticket.total
    assert_equal "cash", ticket.payment_method
    assert_equal BigDecimal("100"), ticket.amount_received
    assert_equal BigDecimal("15"), ticket.change_given
    assert_match(/\AT-\d{6,}\z/, ticket.folio)
    payment = ticket.ticket_payments.sole
    assert_equal BigDecimal("85.00"), payment.amount
    assert_equal @cashier, payment.created_by
    assert_empty result.shortages
  end

  test "stock goes down by the quantity sold, with a movement tied to the sale and the cashier" do
    result = charge([ { method: "cash", amount_received: "85" } ])

    assert_equal 16, products(:pos_cuaderno).reload.stock
    movement = StockMovement.find_by!(sale: result.sale)
    assert_equal products(:pos_cuaderno), movement.product
    assert movement.exit?
    assert_equal 2, movement.qty
    assert_equal @cashier, movement.user
    assert_equal "Venta ##{result.sale.id}", movement.note
    assert_equal 2, @sale.sale_items.first.reload.stock_taken
  end

  test "mixed payment splits cash, card and transfer" do
    sale = open_sale(@cashier, [ products(:pos_cuaderno), 4 ])
    result = charge([ { method: "card", amount: "80" }, { method: "transfer", amount: "50", reference: "SPEI-1" },
                      { method: "cash", amount_received: "50" } ], sale: sale)

    assert_equal "mixed", result.ticket.payment_method
    assert_equal %w[card transfer cash], result.ticket.ticket_payments.map(&:payment_method)
    assert_equal BigDecimal("170.00"), result.ticket.ticket_payments.sum(:amount)
    assert_equal BigDecimal("10"), result.ticket.change_given  # el efectivo cubre 40 y se reciben 50
  end

  test "stock never goes negative: it goes to zero and the missing pieces are reported" do
    sale = open_sale(@cashier, [ products(:pos_pluma), 5 ])
    result = charge([ { method: "cash", amount_received: "45" } ], sale: sale)

    assert_equal 0, products(:pos_pluma).reload.stock
    assert_equal [ { product_id: products(:pos_pluma).id, name: "Pluma azul", missing: 2 } ], result.shortages
    assert_equal 3, sale.sale_items.first.reload.stock_taken
    assert_equal 3, StockMovement.find_by!(sale: sale).qty
  end

  test "an empty stock still lets the sale go through without a movement" do
    products(:pos_pluma).update_columns(stock: 0)
    sale = open_sale(@cashier, [ products(:pos_pluma), 2 ])
    result = charge([ { method: "cash", amount_received: "18" } ], sale: sale)

    assert_equal 2, result.shortages.first[:missing]
    assert_equal 0, sale.sale_items.first.reload.stock_taken
    assert_not StockMovement.exists?(sale: sale)
  end

  test "products that are not counted do not move stock" do
    sale = open_sale(@cashier, [ products(:pos_copia), 10 ])
    charge([ { method: "cash", amount_received: "15" } ], sale: sale)

    assert_not StockMovement.exists?(sale: sale)
    assert_nil sale.sale_items.first.reload.stock_taken
  end

  test "fractional quantities are discounted exactly" do
    sale = open_sale(@cashier, [ products(:pos_liston), "1.5" ])
    charge([ { method: "cash", amount_received: "12" } ], sale: sale)

    assert_equal BigDecimal("24.0"), products(:pos_liston).reload.stock
    assert_equal BigDecimal("1.5"), sale.sale_items.first.reload.stock_taken
  end

  test "a payment that does not cover the total is rejected and nothing is saved" do
    stock = products(:pos_cuaderno).stock
    error = assert_raises(ApiErrors::BaseError) { charge([ { method: "cash", amount_received: "50" } ]) }

    assert_equal "missing", error.details[:code]
    assert @sale.reload.status_open?
    assert_nil @sale.ticket
    assert_equal stock, products(:pos_cuaderno).reload.stock
    assert_not StockMovement.exists?(sale: @sale)
  end

  test "card and transfer cannot exceed the total, and a transfer needs a reference" do
    error = assert_raises(ApiErrors::BaseError) { charge([ { method: "card", amount: "100" } ]) }
    assert_equal "exceeds_total", error.details[:code]
    error = assert_raises(ApiErrors::BaseError) { charge([ { method: "transfer", amount: "85" } ]) }
    assert_equal "reference_required", error.details[:code]
  end

  test "an empty sale cannot be charged" do
    sale = Sale.create!(company: companies(:pos_co), opened_by: @cashier)
    error = assert_raises(ApiErrors::BaseError) { charge([ { method: "cash", amount_received: "10" } ], sale: sale) }
    assert_equal "empty", error.details[:code]
  end

  test "a sale that is already paid cannot be charged again" do
    charge([ { method: "cash", amount_received: "85" } ])
    stock = products(:pos_cuaderno).reload.stock
    error = assert_raises(ApiErrors::BaseError) { charge([ { method: "cash", amount_received: "85" } ]) }

    assert_equal "not_open", error.details[:code]
    assert_equal stock, products(:pos_cuaderno).reload.stock
    assert_equal 1, Ticket.where(sale: @sale).count
  end

  test "an old lock_version is a conflict" do
    stale = @sale.lock_version
    Sales::AddItem.call(@sale, product_id: products(:pos_pluma).id)
    error = assert_raises(ApiErrors::BaseError) { charge([ { method: "cash", amount_received: "200" } ], lock_version: stale) }

    assert_equal :conflict, error.status
    assert_equal "stale_object", error.details[:code]
    assert @sale.reload.status_open?
  end

  test "the lock_version is required" do
    error = assert_raises(ApiErrors::BaseError) do
      Sales::Charge.call(@sale, @cashier, payments: [ { method: "cash", amount_received: "85" } ])
    end
    assert_equal :conflict, error.status
  end

  test "a card payment keeps the terminal only when the terminals module is active" do
    terminal = PaymentTerminal.create!(company: companies(:pos_co), name: "Clip caja", provider: "clip")
    sale = open_sale(@cashier, [ products(:pos_pluma), 1 ])
    result = charge([ { method: "card", amount: "9", terminal_id: terminal.id } ], sale: sale)

    assert_nil result.ticket.ticket_payments.sole.terminal
  end

  test "a sale of fifty items is charged completely" do
    sale = Sale.create!(company: companies(:pos_co), opened_by: @cashier)
    50.times do |i|
      product = companies(:pos_co).products.create!(sku: "BULK-#{i}", name: "Artículo #{i}", price: 10, stock: 5,
                                                    product_type: product_types(:pos_co_counted))
      Sales::AddItem.call(sale, product_id: product.id, quantity: 2)
    end
    result = charge([ { method: "cash", amount_received: "1000" } ], sale: sale)

    assert_equal BigDecimal("1000.00"), result.ticket.total
    assert_equal 50, StockMovement.where(sale: sale).count
    assert result.sale.status_paid?
  end

  test "totals match to the cent: sale, ticket and payments" do
    sale = open_sale(@cashier, [ products(:pos_cuaderno), 3 ], [ products(:pos_pluma), 2 ], [ products(:pos_liston), "2.5" ])
    result = charge([ { method: "cash", amount_received: "500" } ], sale: sale)

    expected = sale.sale_items.sum(:subtotal)
    assert_equal expected, result.sale.total
    assert_equal expected, result.ticket.total
    assert_equal expected, result.ticket.ticket_payments.sum(:amount)
  end
end
