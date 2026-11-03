require "test_helper"

class SaleItemTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pos_co)
    @sale = Sale.create!(company: @company, opened_by: users(:pos_staff))
  end

  def build_item(**attrs)
    SaleItem.new({ sale: @sale, company: @company, product: products(:pos_cuaderno), name: "Cuaderno profesional",
                   sku: "PAP-001", unit_price: 42.5, quantity: 2 }.merge(attrs))
  end

  test "subtotal is quantity times the price at the time, rounded to cents" do
    item = build_item(quantity: 3, unit_price: 1.333).tap(&:save!)
    assert_equal BigDecimal("3.99"), item.subtotal  # el precio se guarda a centavos: 1.33
    assert_equal BigDecimal("85.00"), build_item(quantity: 2).tap(&:valid?).subtotal
  end

  test "quantity must be positive" do
    assert_not build_item(quantity: 0).valid?
    assert_not build_item(quantity: -1).valid?
  end

  test "whole quantities only for types without decimals" do
    assert_not build_item(quantity: 1.5).valid?
    liston = build_item(product: products(:pos_liston), name: "Listón", quantity: 1.5)
    assert liston.valid?
  end

  test "name is required and price cannot be negative" do
    assert_not build_item(name: "").valid?
    assert_not build_item(unit_price: -1).valid?
  end

  test "one row per product in a sale" do
    build_item.save!
    assert_raises(ActiveRecord::RecordNotUnique) { build_item(subtotal: 85).save!(validate: false) }
  end

  test "items cannot be added to a sale that is not open" do
    @sale.update!(status: :paid, paid_at: Time.current, charged_by: users(:pos_staff))
    assert_not build_item.valid?
  end

  test "the product and the sale must belong to the same company" do
    assert_not build_item(product: products(:one)).valid?
    assert_not build_item(company: companies(:one)).valid?
  end

  test "deleting the product keeps the item" do
    item = build_item.tap(&:save!)
    products(:pos_cuaderno).stock_movements.destroy_all
    products(:pos_cuaderno).destroy!
    assert_nil item.reload.product_id
    assert_equal "Cuaderno profesional", item.name
  end
end
