require "test_helper"

class Stock::ReceiveTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @user = users(:resto_waiter)
    @tacos = products(:resto_tacos)
    @cola = products(:resto_cola)
  end

  def receive(items, note: nil) = Stock::Receive.call(company: @company, user: @user, items: items, note: note)

  test "records an entry per product, adds the stock and returns the products" do
    tacos_before = @tacos.stock
    cola_before = @cola.stock

    movements, products = receive([ { product_id: @tacos.id, qty: "12" }, { product_id: @cola.id, qty: 3 } ], note: "Factura 1042")

    assert_equal tacos_before + 12, @tacos.reload.stock
    assert_equal cola_before + 3, @cola.reload.stock
    assert_equal %w[entry entry], movements.map(&:movement_type)
    assert_equal [ "Factura 1042" ], movements.map(&:note).uniq
    assert_equal [ @user.id ], movements.map(&:user_id).uniq
    assert_equal [ @tacos.id, @cola.id ].sort, products.map(&:id).sort
  end

  test "the same product twice adds its quantities in one movement" do
    before = @tacos.stock
    movements, = receive([ { product_id: @tacos.id, qty: 2 }, { product_id: @tacos.id, qty: 3 } ])

    assert_equal 1, movements.size
    assert_equal before + 5, @tacos.reload.stock
  end

  test "the default note says it is a goods receipt" do
    movements, = receive([ { product_id: @tacos.id, qty: 1 } ])

    assert_equal I18n.t("stock.receive.note"), movements.first.note
  end

  test "all or nothing: an invalid line records nothing" do
    before = @tacos.stock
    error = assert_raises(Stock::Receive::Invalid) do
      receive([ { product_id: @tacos.id, qty: 4 }, { product_id: products(:resto_sopa).id, qty: 1 } ])
    end

    assert_equal :not_counted, error.code
    assert_equal products(:resto_sopa), error.product
    assert_equal before, @tacos.reload.stock
  end

  test "rejects empty lists, zero or negative quantities and fractions in whole types" do
    assert_equal :empty_items, assert_raises(Stock::Receive::Invalid) { receive([]) }.code
    assert_equal :invalid_qty, assert_raises(Stock::Receive::Invalid) { receive([ { product_id: @tacos.id, qty: 0 } ]) }.code
    assert_equal :invalid_qty, assert_raises(Stock::Receive::Invalid) { receive([ { product_id: @tacos.id, qty: -2 } ]) }.code
    assert_equal :invalid_qty, assert_raises(Stock::Receive::Invalid) { receive([ { product_id: @tacos.id, qty: "abc" } ]) }.code
    assert_equal :invalid_qty, assert_raises(Stock::Receive::Invalid) { receive([ { product_id: @tacos.id, qty: 1.5 } ]) }.code
  end

  test "accepts fractions in types that allow them" do
    kilos = @company.products.create!(name: "Camarón", sku: "CAM-9", product_type: product_types(:resto_co_supply), stock: 1)
    receive([ { product_id: kilos.id, qty: "2.5" } ])

    assert_equal BigDecimal("3.5"), kilos.reload.stock
  end

  test "a product of another company is not found" do
    assert_raises(ActiveRecord::RecordNotFound) { receive([ { product_id: products(:one).id, qty: 1 } ]) }
  end
end
