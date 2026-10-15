require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "name and sku are required" do
    product = Product.new(company: companies(:one))
    assert_not product.valid?
    assert product.errors[:name].any?
    assert product.errors[:sku].any?
  end

  test "sku is unique within a company" do
    duplicate = Product.new(company: companies(:one), name: "Otro", sku: products(:one).sku)
    assert_not duplicate.valid?
    assert duplicate.errors[:sku].any?
  end

  test "the same sku is allowed in another company" do
    assert Product.new(company: companies(:two), name: "Otro", sku: products(:one).sku).valid?
  end

  test "stock defaults to zero and cannot be negative" do
    product = Product.new(company: companies(:one), name: "Nuevo", sku: "NEW-1")
    assert product.valid?
    assert_equal 0, product.stock
    product.stock = -1
    assert_not product.valid?
    assert product.errors[:stock].any?
  end

  test "stock matches the signed sum of its movements in the fixtures" do
    [ products(:one), products(:two) ].each do |product|
      sum = product.stock_movements.sum do |m|
        m.exit? ? -m.qty.abs : (m.adjustment? ? m.qty : m.qty.abs)
      end
      assert_equal sum, product.stock, "stock desincronizado para #{product.sku}"
    end
  end

  test "search matches name or sku case-insensitively" do
    assert_includes Product.search("contacto"), products(:one)
    assert_includes Product.search("con-001"), products(:one)
    assert_not_includes Product.search("contacto"), products(:two)
    assert_equal Product.count, Product.search("").count
  end

  test "available and by_category scopes" do
    hidden = Product.create!(company: companies(:one), name: "Oculto", sku: "HID-1", available: false, category: "Otro")
    assert_not_includes Product.available, hidden
    assert_includes Product.available, products(:one)
    assert_equal [ hidden ], Product.by_category("Otro").to_a
    assert_includes Product.by_category("Eléctrico"), products(:one)
    assert_equal Product.count, Product.by_category(nil).count
  end

  test "destroying a product removes its movements" do
    product = products(:one)
    assert_difference -> { StockMovement.count }, -product.stock_movements.count do
      product.destroy!
    end
  end
end
