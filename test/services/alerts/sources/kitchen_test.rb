require "test_helper"

class Alerts::Sources::KitchenTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @round = kitchen_orders(:first_round)
    Product.where(company_id: @company.id).update_all(stock: 1000) # que el stock bajo no mezcle las cuentas
  end

  def alerts(kind = nil)
    all = Alerts::Collector.new(@company).call.results
    kind ? all.select { |alert| alert.kind == kind } : all
  end

  def sent_ago(minutes) = KitchenOrder.where(id: @round.id).update_all(sent_at: minutes.minutes.ago)

  def item_ago(item, minutes) = CheckItem.where(id: item.id).update_all(preparing_at: minutes.minutes.ago)

  test "a sent round nobody started alerts after the kitchen limit and groups its items in one alert" do
    sent_ago(15)
    waiting = alerts("kitchen_wait")

    assert_equal 1, waiting.size
    alert = waiting.first
    assert_equal "ko:#{@round.id}:st:#{stations(:kitchen).id}", alert.subject_key
    assert_equal [ 15, 10, "warning" ], [ alert.minutes, alert.threshold_minutes, alert.severity ]
    assert_equal "Mesa 1 · Comanda #1 · Cocina", alert.subject[:label]
    assert_equal({ type: "station", name: "Cocina" }, alert.owner)
    assert_equal check_items(:item_new).check_id, alert.subject[:check_id]
  end

  test "below the limit there is no alert and at twice the limit it is critical" do
    sent_ago(8)
    assert_empty alerts("kitchen_wait")

    sent_ago(25)
    assert_equal "critical", alerts("kitchen_wait").first.severity
  end

  test "the limit depends on the station kind: the bar answers faster than the kitchen" do
    CheckItem.where(id: check_items(:item_ready).id).update_all(status: 1)
    sent_ago(7)

    waiting = alerts("kitchen_wait")
    assert_equal [ stations(:bar).id ], waiting.map { |alert| alert.subject_key[/st:(\d+)/, 1].to_i }
    assert_equal 5, waiting.first.threshold_minutes
  end

  test "a round being prepared alerts after the preparing limit" do
    item_ago(check_items(:item_preparing), 10)
    assert_empty alerts("kitchen_preparing")

    item_ago(check_items(:item_preparing), 30)
    preparing = alerts("kitchen_preparing")
    assert_equal 1, preparing.size
    assert_equal [ 30, 25 ], [ preparing.first.minutes, preparing.first.threshold_minutes ]
  end

  test "ready, delivered and cancelled items never alert, and the alert goes away when the item moves on" do
    sent_ago(40)
    assert_equal 1, alerts("kitchen_wait").size

    CheckItem.where(id: check_items(:item_new).id).update_all(status: 2, preparing_at: Time.current)
    assert_empty alerts("kitchen_wait")

    CheckItem.where(id: check_items(:item_new).id).update_all(status: 3)
    assert_empty alerts("kitchen_preparing").select { |alert| alert.subject_key.include?("st:#{stations(:kitchen).id}") && alert.minutes > 25 }
  end

  test "items of a check that is no longer open do not alert" do
    sent_ago(40)
    Check.where(id: checks(:open_check).id).update_all(status: 1)
    assert_empty alerts("kitchen_wait")
  end

  test "a company without the restaurant module has no round alerts" do
    sent_ago(40)
    @company.update!(disabled_modules: [ "restaurant" ])
    assert_empty alerts
  end
end
