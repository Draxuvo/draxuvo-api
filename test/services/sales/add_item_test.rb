require "test_helper"

class Sales::AddItemTest < ActiveSupport::TestCase
  setup do
    @sale = Sale.create!(company: companies(:pos_co), opened_by: users(:pos_staff))
  end

  def add(**params) = Sales::AddItem.call(@sale, params)

  def error_for(params = {})
    assert_raises(ApiErrors::BaseError) { add(**params) }
  end

  test "adds a product by id with the price and name of the moment" do
    add(product_id: products(:pos_cuaderno).id)
    item = @sale.sale_items.first
    assert_equal "Cuaderno profesional", item.name
    assert_equal "PAP-001", item.sku
    assert_equal BigDecimal("42.50"), item.unit_price
    assert_equal 1, item.quantity
    assert_equal BigDecimal("42.50"), @sale.reload.total
  end

  test "adds by barcode and by sku" do
    add(barcode: "7509990000011")
    add(sku: "PAP-002")
    assert_equal [ products(:pos_cuaderno).id, products(:pos_pluma).id ].sort, @sale.sale_items.pluck(:product_id).sort
  end

  test "scanning the same product again adds one unit and keeps the original price" do
    add(barcode: "7509990000011")
    products(:pos_cuaderno).update!(price: 50)
    add(barcode: "7509990000011")
    item = @sale.sale_items.sole
    assert_equal 2, item.quantity
    assert_equal BigDecimal("42.50"), item.unit_price
    assert_equal BigDecimal("85.00"), @sale.reload.total
  end

  test "accepts a quantity and fractions only for fractional types" do
    add(product_id: products(:pos_cuaderno).id, quantity: "3")
    add(product_id: products(:pos_liston).id, quantity: "1.5")
    assert_equal BigDecimal("12.00"), @sale.sale_items.find_by(product: products(:pos_liston)).subtotal
    assert_equal "invalid_quantity", error_for({ product_id: products(:pos_pluma).id, quantity: "1.5" }).details[:code]
  end

  test "rejects zero, negative and text quantities" do
    %w[0 -1 abc].each do |quantity|
      assert_equal "invalid_quantity", error_for({ product_id: products(:pos_cuaderno).id, quantity: quantity }).details[:code]
    end
  end

  test "rejects products that cannot be sold" do
    assert_equal "product_not_sellable", error_for({ product_id: products(:pos_resma).id }).details[:code]
    assert_equal "product_inactive", error_for({ product_id: products(:pos_inactivo).id }).details[:code]
    assert_equal "product_without_price", error_for({ product_id: products(:pos_sin_precio).id }).details[:code]
    assert_empty @sale.sale_items
  end

  test "unknown code or a product of another company is not found" do
    err = error_for({ barcode: "0000000000000" })
    assert_equal :not_found, err.status
    assert_equal "product_not_found", err.details[:code]
    assert_equal :not_found, error_for({ product_id: products(:one).id }).status
    assert_equal :not_found, error_for({}).status
  end

  test "a sale that is not open does not accept items" do
    @sale.update!(status: :paid, paid_at: Time.current, charged_by: users(:pos_staff))
    assert_equal "not_open", error_for({ product_id: products(:pos_cuaderno).id }).details[:code]
  end

  test "services are sold without tracking stock" do
    add(product_id: products(:pos_copia).id, quantity: "10")
    assert_equal BigDecimal("15.00"), @sale.reload.total
  end
end
