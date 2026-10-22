require "test_helper"
require Rails.root.join("db/migrate/20261022200000_add_menu_and_kind")

# La regla de datos del refactor de Restaurante (spec 032, FR-012b): el insumo sale del menú, todo lo demás queda
# dentro, y las estaciones llamadas "Barra" pasan a ser de tipo barra.
class AddMenuAndKindTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  teardown do
    ProductType.reset_column_information
    Station.reset_column_information
  end

  test "supply types leave the menu, the rest stay in, and a station called Barra becomes a bar" do
    conn = ActiveRecord::Base.connection
    ids = { bar: stations(:bar).id, kitchen: stations(:kitchen).id, supply: product_types(:resto_co_supply).id,
            sold: product_types(:resto_co_sold).id, counted: product_types(:resto_co_counted).id, service: product_types(:one_sold).id }
    conn.remove_column :stations, :kind
    conn.remove_column :product_types, :in_menu
    conn.execute("UPDATE stations SET name = 'barra' WHERE id = #{ids[:bar]}")

    ActiveRecord::Migration.suppress_messages { AddMenuAndKind.new.up }
    ProductType.reset_column_information
    Station.reset_column_information

    assert_equal false, ProductType.find(ids[:supply]).in_menu
    assert_equal true, ProductType.find(ids[:sold]).in_menu
    assert_equal true, ProductType.find(ids[:counted]).in_menu
    assert_equal true, ProductType.find(ids[:service]).in_menu
    assert_equal "bar", Station.find(ids[:bar]).kind
    assert_equal "kitchen", Station.find(ids[:kitchen]).kind
  end
end
