require "test_helper"

class ProductTypes::DefaultsTest < ActiveSupport::TestCase
  test "a new company gets the initial types of its mode, once" do
    restaurant = Company.create!(name: "Mariscos Uno", order_mode: :order)
    assert_equal %w[Platillo Bebida Insumo], restaurant.product_types.ordered.pluck(:name)
    insumo = restaurant.product_types.find_by!(kind: "supply")
    assert_equal [ false, true, true, "kg" ], [ insumo.sellable, insumo.counted, insumo.fractional, insumo.default_unit_key ]

    assert_no_difference -> { restaurant.product_types.count } do
      ProductTypes::Defaults.create_missing(restaurant)
    end

    service = Company.create!(name: "Taller Uno")
    assert_equal %w[Servicio Refacción Material], service.product_types.ordered.pluck(:name)
  end

  test "classify picks the type by how the product is used today" do
    company = companies(:resto_co)
    tracked = Product.new(company: company, tracks_stock: true, available: true)
    hidden = Product.new(company: company, available: false)
    plain = Product.new(company: company, available: true)

    assert_equal "counted_sold", ProductTypes::Defaults.classify(company, tracked).kind
    assert_equal "supply", ProductTypes::Defaults.classify(company, hidden).kind
    assert_equal "sold", ProductTypes::Defaults.classify(company, plain).kind
  end

  test "in a service business a product with stock or a minimum is a counted spare part" do
    company = companies(:one)
    assert_equal "counted_sold", ProductTypes::Defaults.classify(company, Product.new(company: company, stock: 5)).kind
    assert_equal "counted_sold", ProductTypes::Defaults.classify(company, Product.new(company: company, min_stock: 2)).kind
    assert_equal "sold", ProductTypes::Defaults.classify(company, Product.new(company: company)).kind
    # En restaurante la existencia sola no lo vuelve contado: decide "controla inventario".
    assert_equal "sold", ProductTypes::Defaults.classify(companies(:resto_co), Product.new(company: companies(:resto_co), stock: 50)).kind
  end

  test "initial types come with the suggested icon of their mode" do
    restaurant = Company.create!(name: "Mariscos Dos", order_mode: :order)
    assert_equal %w[utensils cup box], restaurant.product_types.ordered.pluck(:icon)

    service = Company.create!(name: "Taller Dos")
    assert_equal %w[wrench gear box], service.product_types.ordered.pluck(:icon)
  end
end
