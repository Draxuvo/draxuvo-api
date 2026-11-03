require "test_helper"

class Sales::CancelTest < ActiveSupport::TestCase
  setup do
    @cashier = users(:pos_staff)
    @admin = users(:pos_admin)
    @sale = open_sale(@cashier, [ products(:pos_cuaderno), 2 ], [ products(:pos_pluma), 5 ])
    charge_cash(@sale, @cashier, received: 200)
    @sale.reload
  end

  def cancel(reason = "Cliente devolvió todo", user: @admin) = Sales::Cancel.call(@sale, user, reason)

  test "marks the sale cancelled with who, when and why" do
    cancel

    assert @sale.reload.status_cancelled?
    assert_equal @admin, @sale.cancelled_by
    assert_equal "Cliente devolvió todo", @sale.cancel_reason
    assert_not_nil @sale.cancelled_at
    assert_equal @cashier, @sale.charged_by
  end

  test "voids the ticket and its payments, keeping the folio" do
    folio = @sale.ticket.folio
    cancel

    ticket = @sale.reload.ticket
    assert ticket.voided?
    assert_equal folio, ticket.folio
    assert_equal @admin, ticket.voided_by
    assert_equal "Cliente devolvió todo", ticket.void_reason
    assert ticket.ticket_payments.all? { |p| p.voided_at.present? }
    assert_empty ticket.ticket_payments.active
  end

  test "returns exactly what was discounted, not what was sold" do
    # pluma: había 3 y se vendieron 5 → se descontaron 3 (quedó en 0); cuaderno: 18 − 2 = 16
    assert_equal 0, products(:pos_pluma).reload.stock
    assert_equal 16, products(:pos_cuaderno).reload.stock
    cancel

    assert_equal 18, products(:pos_cuaderno).reload.stock
    assert_equal 3, products(:pos_pluma).reload.stock
    movements = StockMovement.where(sale: @sale, movement_type: :entry)
    assert_equal 2, movements.count
    assert_equal [ @admin.id ], movements.pluck(:user_id).uniq
    assert_equal "Cancelación de venta ##{@sale.id}", movements.first.note
  end

  test "cancelling twice does not return stock again" do
    cancel
    stock = products(:pos_cuaderno).reload.stock
    error = assert_raises(ApiErrors::BaseError) { cancel }

    assert_equal "not_paid", error.details[:code]
    assert_equal stock, products(:pos_cuaderno).reload.stock
  end

  test "the reason is required" do
    [ "", "   ", nil ].each do |reason|
      error = assert_raises(ApiErrors::BaseError) { cancel(reason) }
      assert_equal "reason_required", error.details[:code]
    end
    assert @sale.reload.status_paid?
    assert @sale.ticket.paid?
  end

  test "an open sale cannot be cancelled" do
    open = open_sale(@cashier, [ products(:pos_cuaderno), 1 ])
    error = assert_raises(ApiErrors::BaseError) { Sales::Cancel.call(open, @admin, "x") }
    assert_equal "not_paid", error.details[:code]
  end

  test "products that are not counted and deleted products are skipped without failing" do
    sale = open_sale(@cashier, [ products(:pos_copia), 4 ], [ products(:pos_liston), "1.5" ])
    charge_cash(sale, @cashier, received: 100)
    sale.sale_items.find_by(product: products(:pos_liston)).update_columns(product_id: nil)

    assert_nothing_raised { Sales::Cancel.call(sale.reload, @admin, "Error de captura") }
    assert sale.reload.status_cancelled?
    assert_not StockMovement.exists?(sale: sale, movement_type: :entry)
  end

  test "fractional quantities come back exactly" do
    sale = open_sale(@cashier, [ products(:pos_liston), "2.5" ])
    charge_cash(sale, @cashier, received: 20)
    assert_equal BigDecimal("23.0"), products(:pos_liston).reload.stock

    Sales::Cancel.call(sale.reload, @admin, "Devolución")
    assert_equal BigDecimal("25.5"), products(:pos_liston).reload.stock
  end

  test "a failure in the middle leaves the sale paid" do
    StockMovement.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      assert_raises(ActiveRecord::RecordInvalid) { cancel }
    end

    assert @sale.reload.status_paid?
    assert @sale.ticket.paid?
    assert_empty @sale.ticket.ticket_payments.where.not(voided_at: nil)
  end

  test "the cancelled sale no longer counts as income" do
    cancel
    income = Reports::IncomeService.new(companies(:pos_co), 1.day.ago..1.day.from_now, :day).call
    assert_equal 0, income[:total_tickets]
  end
end
