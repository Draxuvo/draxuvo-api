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

  test "icon must be a catalog key; blank becomes nil" do
    product = companies(:resto_co).products.new(name: "X", sku: "X", product_type: product_types(:resto_co_sold))
    product.icon = "taco"
    assert product.valid?
    product.icon = "nope"
    assert_not product.valid?
    assert product.errors.key?(:icon)
    product.icon = ""
    assert product.valid?
    assert_nil product.icon
  end

  # --- Spec 054 (H-48): un tipo que no existe no cae en silencio en el de por omisión ---

  test "a product with a product type id that does not exist is invalid" do
    product = Product.new(company: companies(:one), sku: "TIPO-FANTASMA", name: "Fantasma", product_type_id: 99_999_999)
    assert_not product.valid?
    assert_includes product.errors.attribute_names, :product_type
  end

  test "a product without a product type still gets the default one" do
    product = Product.new(company: companies(:one), sku: "TIPO-OMITIDO", name: "Sin tipo")
    assert product.valid?, product.errors.full_messages.to_sentence
    assert_not_nil product.product_type
  end

  # --- Spec 059: una sola consulta para Tomar pedido y el menú público ---

  test "menu_for in order mode keeps available products of sellable types in the menu" do
    company = companies(:resto_co)
    product_types(:resto_co_counted).update!(in_menu: false)
    products(:resto_agua).update!(available: false)
    supply = company.products.create!(sku: "INSUMO-059", name: "Harina", product_type: product_types(:resto_co_supply), price: 1)

    names = Product.menu_for(company).map(&:name)
    assert_includes names, "Sopa del día"
    assert_not_includes names, "Tacos al pastor", "tipo fuera del menú"
    assert_not_includes names, "Agua de horchata", "no disponible"
    assert_not_includes names, supply.name, "no se vende"
  end

  test "menu_for in service mode uses every sellable type and orders by category and name" do
    company = companies(:resto_co)
    company.update!(order_mode: :service)
    product_types(:resto_co_counted).update!(in_menu: false)

    list = Product.menu_for(company).to_a
    assert_includes list.map(&:name), "Tacos al pastor", "en modo servicio no importa in_menu"
    assert_equal list.sort_by { |p| [ p.category.to_s, p.name ] }.map(&:id), list.map(&:id)
  end
end
