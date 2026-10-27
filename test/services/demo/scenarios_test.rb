require "test_helper"

class Demo::ScenariosTest < ActiveSupport::TestCase
  def provision(key)
    Demo::Provision.call(plan: Demo::Scenarios.plan_of(key), scenario: key, locale: "es")
  end

  test "registry maps every scenario to a plan and plans to scenarios" do
    assert_equal %w[basic_retail enterprise_restaurant pro_restaurant pro_service], Demo::Scenarios.keys.sort
    assert_equal %w[pro_restaurant pro_service], Demo::Scenarios.for_plan(:pro).sort
    assert Demo::Scenarios.valid?("pro", "pro_service")
    assert_not Demo::Scenarios.valid?("basic", "pro_service")
  end

  Demo::Scenarios.keys.each do |key|
    test "#{key} has exactly the modules of its plan and complete data" do
      result = provision(key)
      company = result.company

      assert company.demo?
      assert_equal Plan.find(Demo::Scenarios.plan_of(key)).modules.sort, company.active_modules.sort
      assert_operator company.employees.active.where.not(salary: nil).count, :>=, 4
      assert_operator company.attendances.where("checkin_at >= ?", 10.days.ago).count, :>=, 20
      assert_operator company.attendances.where(checkin_at: Time.zone.today.all_day).count, :>=, 2
      assert_operator company.products.count, :>=, 12
      assert company.products.all? { |product| product.stock_movements.exists? || product.stock.to_i.zero? }
      run = company.payroll_runs.first
      assert run, "debe traer una corrida de nómina"
      assert run.paid?
    end

    test "#{key} is deterministic: same names and amounts on every visit" do
      snapshot = lambda do |result|
        company = result.company
        [ company.employees.order(:name).pluck(:name, :salary), company.products.order(:sku).pluck(:sku, :name, :price),
          company.payroll_runs.order(:id).pluck(:total_cents) ]
      end

      assert_equal snapshot.call(provision(key)), snapshot.call(provision(key))
    end
  end

  test "basic_retail names its product types for a grocery store" do
    company = provision("basic_retail").company

    assert_equal %w[Insumo Mercancía Servicio], company.product_types.pluck(:name).sort
    assert_equal [ "Mercancía" ], company.products.includes(:product_type).map { |p| p.product_type.name }.uniq
  end

  test "basic_retail has no orders, restaurant or terminals" do
    company = provision("basic_retail").company

    assert_equal 0, company.work_orders.count
    assert_equal 0, company.checks.count
    assert_equal 0, company.dining_tables.count
  end

  test "pro_service has work orders in every state and paid tickets and terminals" do
    company = provision("pro_service").company

    assert company.order_mode_service?
    assert_equal %w[done in_progress open paid], company.work_orders.distinct.pluck(:status).sort & %w[done in_progress open paid]
    assert company.tickets.paid.exists?
    assert company.payment_terminals.exists?
  end

  test "restaurants have stations, tables and checks open, to pay and closed today, and low stock" do
    %w[pro_restaurant enterprise_restaurant].each do |key|
      company = provision(key).company

      assert company.order_mode_order?
      assert_equal %w[Barra Cocina], company.stations.order(:name).pluck(:name)
      assert_operator company.dining_tables.count, :>=, 8
      open_checks = company.checks.status_open.to_a
      states = open_checks.map { |check| Restaurant::TableState.call(check) }
      assert_includes states, "occupied"
      assert_includes states, "to_pay"
      assert company.checks.status_closed.where(closed_at: Time.zone.today.all_day).exists?
      assert company.tickets.paid.exists?
      assert_operator Restaurant::Availability.new(company).alerts.size, :>=, 2
    end
  end

  test "enterprise_restaurant has a branch and the owner is a member of both" do
    result = provision("enterprise_restaurant")

    assert result.branch
    assert result.branch.demo?
    assert_equal result.company, result.branch.parent
    assert_equal [ result.branch.id, result.company.id ].sort, result.user.user_companies.pluck(:company_id).sort
    assert result.branch.employees.exists?
  end
end
