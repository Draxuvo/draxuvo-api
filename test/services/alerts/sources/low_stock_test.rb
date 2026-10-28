require "test_helper"

class Alerts::Sources::LowStockTest < ActiveSupport::TestCase
  setup { @company = companies(:resto_co) }

  def alerts = Alerts::Collector.new(@company).call.results.select { |alert| alert.kind == "low_stock" }

  test "it uses the same rule as the inventory: counted type, a minimum, stock at or below it" do
    assert_equal Product.where(company_id: @company.id).low_stock.pluck(:id).sort, alerts.map { |alert| alert.subject[:id] }.sort

    cola = alerts.sole
    assert_equal products(:resto_cola).id, cola.subject[:id]
    assert_equal "Refresco de cola", cola.subject[:label]
    assert_equal [ 2, 3, "warning", "product:#{cola.subject[:id]}" ], [ cola.stock, cola.min_stock, cola.severity, cola.subject_key ]
    assert_nil cola.minutes
  end

  test "it is critical when nothing is left and goes away when restocked" do
    Product.where(id: products(:resto_cola).id).update_all(stock: 0)
    assert_equal "critical", alerts.sole.severity

    Product.where(id: products(:resto_cola).id).update_all(stock: 10)
    assert_empty alerts
  end

  test "a product without a minimum or of a type that is not counted never alerts" do
    Product.where(id: products(:resto_cola).id).update_all(min_stock: 0)
    assert_empty alerts

    Product.where(id: products(:resto_sopa).id).update_all(stock: 0, min_stock: 5)
    assert_empty alerts
  end

  test "it needs the inventory module and the company's own products" do
    @company.update!(disabled_modules: [ "inventory" ])
    assert_empty alerts

    assert_empty Alerts::Collector.new(companies(:pro_co)).call.results.select { |alert| alert.subject[:id] == products(:resto_cola).id }
  end

  test "low stock cannot be snoozed even if a row exists for it" do
    @company.alert_snoozes.build(kind: "low_stock", subject_key: "product:1", snoozed_until: 1.hour.from_now).tap { |snooze| assert_not snooze.valid? }
  end
end
