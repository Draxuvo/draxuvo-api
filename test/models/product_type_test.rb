require "test_helper"

class ProductTypeTest < ActiveSupport::TestCase
  setup { @company = companies(:resto_co) }

  test "the name is unique per company ignoring case and decimals require counting" do
    dup = @company.product_types.build(name: " platillo ")
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: "platillo")

    loose = @company.product_types.build(name: "Postre", counted: false, fractional: true)
    assert_not loose.valid?
    assert loose.errors.key?(:fractional)
    assert_not @company.product_types.build(name: "Raro", default_unit_key: "xyz").valid?
  end

  test "changing counted syncs the inventory tracking of its products" do
    type = product_types(:resto_co_sold)
    type.update!(counted: true)
    assert products(:resto_sopa).reload.tracks_stock
    type.update!(counted: false)
    assert_not products(:resto_sopa).reload.tracks_stock
  end

  test "decimals cannot be turned off while a product has a fraction" do
    supply = product_types(:resto_co_supply)
    @company.products.create!(name: "Camarón", sku: "CAM", product_type: supply, stock: 2.5)
    assert_not supply.update(fractional: false)
    assert supply.errors.added?(:fractional, :fractional_stock)
    assert_equal [ "Camarón" ], supply.products_with_fractions
  end

  test "a type with products cannot be destroyed" do
    assert_not product_types(:resto_co_counted).destroy
    assert product_types(:resto_co_supply).destroy
  end

  test "icon must be a catalog key; blank becomes nil" do
    type = product_types(:resto_co_sold)
    type.icon = "pizza"
    assert type.valid?
    type.icon = "nope"
    assert_not type.valid?
    type.icon = " "
    type.icon = ""
    assert type.valid?
    assert_nil type.icon
  end
end
