require "test_helper"

class Restaurant::SendRoundTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @check = checks(:open_check) # tiene un artículo sin mandar: agua de horchata
    @context = Restaurant::Permissions::Context.new(user: users(:resto_waiter), role: "staff")
  end

  def add_draft(product, quantity: 1)
    @check.check_items.create!(company: @company, product: product, name: product.name,
                               unit_price: product.price, quantity: quantity)
  end

  test "sends the drafts as a new numbered round" do
    result = Restaurant::SendRound.call(@check, @context)

    assert_equal 2, result.kitchen_order.number
    assert_equal [ "Agua de horchata" ], result.sent.map(&:name)
    assert check_items(:item_draft).reload.status_new?
    assert_equal result.kitchen_order, check_items(:item_draft).kitchen_order
    assert_equal users(:resto_waiter), result.kitchen_order.sent_by
  end

  test "an item without a station of its own goes to the default station" do
    Restaurant::SendRound.call(@check, @context)

    assert_equal stations(:kitchen), check_items(:item_draft).reload.station
  end

  test "an item goes to the station of its product" do
    products(:resto_agua).update!(station: stations(:bar))
    Restaurant::SendRound.call(@check, @context)

    assert_equal stations(:bar), check_items(:item_draft).reload.station
  end

  test "a tracked item that does not fit is rejected and stays a draft while the rest goes out" do
    cola = add_draft(products(:resto_cola), quantity: 5) # quedan 1 disponible
    result = Restaurant::SendRound.call(@check, @context)

    assert_equal [ cola ], result.rejected.map(&:first)
    assert_equal [ 1 ], result.rejected.map(&:last)
    assert cola.reload.status_draft?
    assert check_items(:item_draft).reload.status_new?
  end

  test "when everything is rejected no round is created" do
    check_items(:item_draft).destroy!
    add_draft(products(:resto_cola), quantity: 5)

    result = Restaurant::SendRound.call(@check, @context)

    assert_nil result.kitchen_order
    assert_equal 1, @check.kitchen_orders.count
  end

  test "an item that exactly fits is sent" do
    add_draft(products(:resto_tacos), quantity: 9) # 10 en inventario menos 1 comprometido

    result = Restaurant::SendRound.call(@check, @context)

    assert_empty result.rejected
  end

  test "two drafts of the same product share what is left" do
    add_draft(products(:resto_tacos), quantity: 6)
    second = add_draft(products(:resto_tacos), quantity: 6)

    result = Restaurant::SendRound.call(@check, @context)

    assert_equal [ second ], result.rejected.map(&:first)
  end

  test "nothing to send raises" do
    check_items(:item_draft).destroy!

    error = assert_raises(ApiErrors::UnprocessableEntityError) { Restaurant::SendRound.call(@check, @context) }
    assert_equal "nothing_to_send", error.details[:code]
  end

  test "a check that is not open cannot send" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      Restaurant::SendRound.call(checks(:closed_check), @context)
    end
    assert_equal "check_not_open", error.details[:code]
  end

  test "without any station the round fails and nothing is saved" do
    @company.stations.update_all(active: false, is_default: false)

    assert_raises(ApiErrors::UnprocessableEntityError) { Restaurant::SendRound.call(@check, @context) }
    assert check_items(:item_draft).reload.status_draft?
    assert_equal 1, @check.kitchen_orders.count
  end
end
