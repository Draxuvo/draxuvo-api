require "test_helper"

class Restaurant::AvailabilityTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @availability = Restaurant::Availability.new(@company)
  end

  test "available is the stock minus what open checks already committed" do
    assert_equal 9, @availability.available_qty(products(:resto_tacos)), "10 en inventario, 1 en la cuenta abierta"
  end

  test "a product that does not track stock has no quantity and is never sold out" do
    sopa = products(:resto_sopa)

    assert_nil @availability.available_qty(sopa)
    assert_not @availability.sold_out?(sopa)
  end

  test "sold out when committed reaches the stock" do
    cola = products(:resto_cola) # 2 en inventario, 1 comprometido
    assert_equal 1, @availability.available_qty(cola)

    checks(:takeout_check).check_items.create!(company: @company, product: cola, name: cola.name, unit_price: 30, quantity: 1)
      .update!(status: :new, kitchen_order: kitchen_orders(:first_round))
    availability = Restaurant::Availability.new(@company)

    assert availability.sold_out?(cola)
  end

  test "drafts and closed checks commit nothing" do
    agua = products(:resto_agua)
    assert_equal 0, @availability.committed.fetch(agua.id, 0)
    assert_equal 1, @availability.committed.fetch(products(:resto_tacos).id), "solo la cuenta abierta suma, no la cerrada"
  end

  test "low when the stock is at or under the minimum" do
    assert @availability.low?(products(:resto_cola))
    assert_not @availability.low?(products(:resto_tacos))
    assert_not @availability.low?(products(:resto_sopa)), "no controla inventario"
  end

  test "alerts lists tracked products that are low or sold out" do
    names = @availability.alerts.map(&:name)

    assert_equal [ "Refresco de cola" ], names
  end

  test "another company's committed items do not count" do
    other = Restaurant::Availability.new(companies(:pro_co))

    assert_empty other.committed
  end
end
