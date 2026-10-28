require "test_helper"

class Alerts::Sources::WorkOrderStalledTest < ActiveSupport::TestCase
  setup { @company = companies(:pro_co) }

  def alerts = Alerts::Collector.new(@company).call.results.select { |alert| alert.kind == "work_order_stalled" }

  test "an open order is measured from its creation and an in-progress one from when it started" do
    assert_empty alerts

    WorkOrder.where(id: work_orders(:pro_open).id).update_all(created_at: 2.days.ago)
    WorkOrder.where(id: work_orders(:pro_started).id).update_all(started_at: 3.days.ago)

    found = alerts.index_by { |alert| alert.subject[:id] }
    assert_equal [ work_orders(:pro_open).id, work_orders(:pro_started).id ].sort, found.keys.sort
    assert_equal 1440, found[work_orders(:pro_open).id].threshold_minutes
    assert_equal "Orden ##{work_orders(:pro_open).id} · Instalar contactos", found[work_orders(:pro_open).id].subject[:label]
    assert_equal({ type: "employee", name: "Empleado Pro" }, found[work_orders(:pro_open).id].owner)
    assert_equal "critical", found[work_orders(:pro_started).id].severity
  end

  test "done, paid and cancelled orders never alert" do
    WorkOrder.where(id: [ work_orders(:pro_done).id, work_orders(:pro_paid).id, work_orders(:pro_cancelled).id ])
             .update_all(created_at: 10.days.ago, started_at: 10.days.ago)
    assert_empty alerts
  end

  test "an order that moves on loses the alert" do
    WorkOrder.where(id: work_orders(:pro_open).id).update_all(created_at: 2.days.ago)
    assert_equal 1, alerts.size

    WorkOrder.where(id: work_orders(:pro_open).id).update_all(status: 2)
    assert_empty alerts
  end

  test "the limit is the company's own setting" do
    WorkOrder.where(id: work_orders(:pro_open).id).update_all(created_at: 3.hours.ago)
    assert_empty alerts

    AlertSetting.create!(company: @company, thresholds: { "work_order_stalled" => 60 })
    assert_includes alerts.map { |alert| alert.subject[:id] }, work_orders(:pro_open).id
    assert_equal 60, alerts.first.threshold_minutes
  end

  test "orders of another company or a company without the module do not alert" do
    WorkOrder.where(id: work_orders(:pro_open).id).update_all(created_at: 2.days.ago)
    assert_empty Alerts::Collector.new(companies(:resto_co)).call.results.select { |alert| alert.kind == "work_order_stalled" }

    @company.update!(disabled_modules: [ "work_orders" ])
    assert_empty alerts
  end
end
