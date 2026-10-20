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

  # --- spec 016: el tipo decide existencia, menú y alerta ---

  test "the type decides tracking, whole quantities and the sellable and low_stock scopes" do
    company = companies(:resto_co)
    supply = company.products.create!(name: "Limón", sku: "LIM", product_type: product_types(:resto_co_supply), stock: 2.5, min_stock: 5)
    dish = products(:resto_sopa)

    assert supply.tracks_stock
    assert_not dish.tracks_stock
    assert_not company.products.new(name: "Coca", sku: "COC", product_type: product_types(:resto_co_counted), stock: 1.5).valid?
    assert_not_includes Product.sellable, supply
    assert_includes Product.sellable, dish
    assert_includes Product.low_stock, supply
    assert_not_includes Product.low_stock, dish
    assert_equal "kg", supply.unit.key
  end

  test "a type from another company is rejected" do
    assert_not companies(:resto_co).products.new(name: "X", sku: "X", product_type: product_types(:one_sold)).valid?
  end
end
