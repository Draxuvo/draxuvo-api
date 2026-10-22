require "test_helper"

class Reports::ModulesTest < ActiveSupport::TestCase
  setup { @company = Company.create!(name: "Reportes Módulos") }

  def modules = Reports::Modules.new(@company.reload)

  test "basic plan has expenses, payroll, attendance and inventory but no income or work orders" do
    @company.subscription.update!(plan: :basic)

    assert modules.inventory?
    assert modules.payroll?
    assert modules.expenses?
    assert modules.attendance?
    assert_not modules.income?
    assert_not modules.work_orders?
  end

  test "pro plan has everything" do
    @company.subscription.update!(plan: :pro)

    assert modules.income?
    assert modules.work_orders?
    assert modules.inventory?
    assert modules.attendance?
  end

  test "income follows the modules, not the plan name" do
    @company.subscription.update!(plan: :pro)
    @company.update!(disabled_modules: %w[tickets restaurant work_orders])

    assert_not modules.income?
  end

  test "attendance needs employees and attendance" do
    @company.subscription.update!(plan: :basic)
    @company.update!(disabled_modules: %w[attendance])
    assert_not modules.attendance?

    @company.update!(disabled_modules: %w[employees])
    assert_not modules.attendance?
    assert_not modules.payroll?
  end

  test "a company without a subscription has nothing" do
    @company.subscription.destroy!

    assert_not modules.inventory?
    assert_not modules.expenses?
  end
end
