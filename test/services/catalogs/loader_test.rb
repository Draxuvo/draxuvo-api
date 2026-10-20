require "test_helper"

# Carga de catálogo inicial desde YAML (db/catalogs/*.yml).
class Catalogs::LoaderTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
  end

  def data(extra = {})
    {
      "order_mode" => "order",
      "stations" => %w[Cocina Barra],
      "tables" => [ 1, 2 ],
      "terminals" => [ { "name" => "Terminal caja", "provider" => "bbva" } ],
      "products" => [
        { "sku" => "T-1", "name" => "Tostada", "category" => "Tostadas", "price" => 25, "station" => "Cocina" },
        { "sku" => "T-2", "name" => "Corona", "category" => "Cerveza", "price" => 25, "station" => "Barra",
          "tracks_stock" => true, "stock" => 24, "min_stock" => 6 }
      ]
    }.merge(extra)
  end

  test "loads stations, tables, terminals and products with the initial stock" do
    result = Catalogs::Loader.call(data, owner_email: @owner.email)

    assert_equal @company, result.company
    assert @company.reload.order_mode_order?
    assert @company.stations.exists?(name: "Barra")
    assert @company.dining_tables.exists?(name: "2")
    assert @company.payment_terminals.exists?(name: "Terminal caja", provider: "bbva")
    corona = @company.products.find_by!(sku: "T-2")
    assert_equal 24, corona.stock
    assert_equal "Barra", corona.station.name
    assert_equal 1, corona.stock_movements.count
  end

  test "running it again updates prices without duplicating stock or records" do
    Catalogs::Loader.call(data, owner_email: @owner.email)
    changed = data
    changed["products"][1] = changed["products"][1].merge("price" => 30)

    assert_no_difference %w[Product.count StockMovement.count DiningTable.count Station.count PaymentTerminal.count] do
      Catalogs::Loader.call(changed, owner_email: @owner.email)
    end
    corona = @company.products.find_by!(sku: "T-2")
    assert_equal 30, corona.price
    assert_equal 24, corona.stock
  end

  test "stock added later to an already loaded product is entered once" do
    plain = data("products" => [ { "sku" => "T-3", "name" => "Victoria", "price" => 25, "station" => "Barra" } ])
    Catalogs::Loader.call(plain, owner_email: @owner.email)
    tracked = data("products" => [ { "sku" => "T-3", "name" => "Victoria", "price" => 38, "station" => "Barra",
                                     "tracks_stock" => true, "stock" => 500, "min_stock" => 50 } ])
    2.times { Catalogs::Loader.call(tracked, owner_email: @owner.email) }

    victoria = @company.products.find_by!(sku: "T-3")
    assert_equal 500, victoria.stock
    assert victoria.tracks_stock
    assert_equal 1, victoria.stock_movements.count
  end

  test "an unknown station or an owner of nothing stops the load" do
    bad = data("products" => [ { "sku" => "X", "name" => "X", "station" => "Terraza" } ])
    assert_raises(ArgumentError) { Catalogs::Loader.call(bad, owner_email: @owner.email) }
    assert_not @company.products.exists?(sku: "X")

    assert_raises(ArgumentError) { Catalogs::Loader.call(data, owner_email: users(:resto_waiter).email) }
  end

  test "the Aquí me quedo catalog file loads" do
    file = YAML.safe_load_file(Rails.root.join("db/catalogs/aqui_me_quedo.yml"))
    result = Catalogs::Loader.call(file, owner_email: @owner.email)
    assert_equal 45, result.created["products"]
    assert_equal 90, @company.products.find_by!(sku: "AMQ-CAM-DIA").price
  end
end
