require "test_helper"

class SaleTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pos_co)
    @cashier = users(:pos_staff)
  end

  def build_sale(**attrs)
    Sale.new({ company: @company, opened_by: @cashier }.merge(attrs))
  end

  test "a new sale is open, empty and valid" do
    sale = build_sale
    assert sale.valid?
    assert sale.status_open?
    assert_equal 0, sale.total
  end

  test "total cannot be negative" do
    assert_not build_sale(total: -1).valid?
  end

  test "recalculate_total! is the sum of the items" do
    sale = build_sale.tap(&:save!)
    sale.sale_items.create!(company: @company, product: products(:pos_cuaderno), name: "Cuaderno", unit_price: 42.5, quantity: 2)
    sale.sale_items.create!(company: @company, product: products(:pos_pluma), name: "Pluma", unit_price: 9, quantity: 1)
    sale.recalculate_total!
    assert_equal BigDecimal("94.00"), sale.reload.total
  end

  test "a cancelled sale needs reason, date, canceller, payer and paid date" do
    sale = build_sale.tap(&:save!)
    sale.status = :cancelled
    assert_not sale.valid?
    sale.assign_attributes(cancel_reason: "Error", cancelled_at: Time.current, cancelled_by: users(:pos_admin),
                           paid_at: Time.current, charged_by: @cashier)
    assert sale.valid?
  end

  test "a paid sale needs who charged and when" do
    sale = build_sale.tap(&:save!)
    sale.status = :paid
    assert_not sale.valid?
    sale.assign_attributes(paid_at: Time.current, charged_by: @cashier)
    assert sale.valid?
  end

  test "a paid sale cannot change its total" do
    sale = build_sale.tap(&:save!)
    sale.update!(status: :paid, paid_at: Time.current, charged_by: @cashier)
    sale.total = 10
    assert_not sale.valid?
  end

  test "the sale has at most one ticket" do
    sale = build_sale.tap(&:save!)
    Ticket.create!(sale: sale, company: @company, total: 10)
    assert_raises(ActiveRecord::RecordNotUnique) do
      Ticket.new(sale: sale, company: @company, total: 10, folio: "T-DUP").save!(validate: false)
    end
  end

  test "lock_version guards simultaneous edits" do
    sale = build_sale.tap(&:save!)
    stale = Sale.find(sale.id)
    sale.update!(total: 5)
    stale.total = 7
    assert_raises(ActiveRecord::StaleObjectError) { stale.save! }
  end
end
