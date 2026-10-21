require "test_helper"

# Catálogo de iconos de producto (spec 026).
class ProductIconsTest < ActiveSupport::TestCase
  test "the catalog has 54 unique keys in six groups" do
    assert_equal 54, ProductIcons.keys.size
    assert_equal ProductIcons.keys.uniq, ProductIcons.keys
    assert_equal %w[comida bebida postre plomeria_y_oficios refacciones_y_materiales general], ProductIcons.groups.keys
  end

  test "valid? only accepts catalog keys" do
    assert ProductIcons.valid?("taco")
    assert_not ProductIcons.valid?("nope")
    assert_not ProductIcons.valid?(nil)
  end

  test "default_for suggests an icon by type kind and mode" do
    assert_equal "utensils", ProductIcons.default_for("sold", "order")
    assert_equal "wrench", ProductIcons.default_for("sold", "service")
    assert_equal "gear", ProductIcons.default_for("counted_sold", "service")
    assert_equal "box", ProductIcons.default_for("supply", "order")
    assert_nil ProductIcons.default_for("custom", "order")
  end

  test "every default is a catalog key" do
    ProductIcons::DEFAULTS.each_value { |kinds| kinds.each_value { |key| assert ProductIcons.valid?(key) } }
  end
end
