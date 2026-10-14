require "test_helper"

# Catálogo de planes (PORO, data-model.md "Plan"). FR-023.
class PlanTest < ActiveSupport::TestCase
  EXPECTED_PRICES = {
    basic:      { monthly: 39_900,  annual: 399_000 },
    pro:        { monthly: 70_000,  annual: 700_000 },
    enterprise: { monthly: 129_900, annual: 1_299_000 }
  }.freeze

  EXPECTED_MODULES = {
    basic:      %i[employees attendance inventory],
    pro:        %i[employees attendance inventory work_orders tickets reports],
    enterprise: %i[employees attendance inventory work_orders tickets reports whatsapp multi_company]
  }.freeze

  test "keys are basic, pro and enterprise in that order" do
    assert_equal %i[basic pro enterprise], Plan.keys
    assert_equal %i[basic pro enterprise], Plan.all.map(&:key)
  end

  test "keys match the Subscription plan enum" do
    assert_equal Subscription.plans.keys.map(&:to_sym).sort, Plan.keys.sort
  end

  test "MODULES lists the eight modules in order" do
    assert_equal %i[employees attendance inventory work_orders tickets reports whatsapp multi_company],
                 Plan::MODULES
  end

  test "find accepts symbols and strings" do
    assert_equal :pro, Plan.find(:pro).key
    assert_equal :pro, Plan.find("pro").key
  end

  test "find raises with an unknown key" do
    plan_class = Plan
    assert_raises(StandardError) { plan_class.find(:starter) }
    assert_raises(StandardError) { plan_class.find(:business) }
  end

  test "monthly and annual amounts match the catalog" do
    EXPECTED_PRICES.each do |key, prices|
      plan = Plan.find(key)
      assert_equal prices[:monthly], plan.monthly_amount_cents, "#{key} monthly"
      assert_equal prices[:annual], plan.annual_amount_cents, "#{key} annual"
      assert_equal prices[:monthly], plan.amount_cents(:monthly), "#{key} amount_cents(:monthly)"
      assert_equal prices[:annual], plan.amount_cents("annual"), "#{key} amount_cents('annual')"
    end
  end

  test "annual costs exactly ten times monthly for every plan" do
    Plan.all.each do |plan|
      assert_equal plan.monthly_amount_cents * 10, plan.annual_amount_cents, "#{plan.key}"
    end
  end

  test "lookup_key is draxuvo_<plan>_<cycle>" do
    assert_equal "draxuvo_pro_monthly", Plan.find(:pro).lookup_key(:monthly)
    assert_equal "draxuvo_pro_annual", Plan.find(:pro).lookup_key("annual")
    assert_equal "draxuvo_basic_monthly", Plan.find(:basic).lookup_key(:monthly)
    assert_equal "draxuvo_enterprise_annual", Plan.find(:enterprise).lookup_key(:annual)
  end

  test "there are six distinct lookup keys" do
    keys = Plan.all.flat_map { |plan| %i[monthly annual].map { |cycle| plan.lookup_key(cycle) } }
    assert_equal 6, keys.uniq.size
  end

  test "parse_lookup_key returns plan and cycle" do
    assert_equal [ :pro, :monthly ], normalize(Plan.parse_lookup_key("draxuvo_pro_monthly"))
    assert_equal [ :basic, :annual ], normalize(Plan.parse_lookup_key("draxuvo_basic_annual"))
    assert_equal [ :enterprise, :monthly ], normalize(Plan.parse_lookup_key("draxuvo_enterprise_monthly"))
  end

  test "parse_lookup_key round-trips every lookup_key" do
    Plan.all.each do |plan|
      %i[monthly annual].each do |cycle|
        assert_equal [ plan.key, cycle ], normalize(Plan.parse_lookup_key(plan.lookup_key(cycle)))
      end
    end
  end

  test "parse_lookup_key returns nil for unknown formats" do
    [
      nil,
      "",
      "draxuvo_starter_monthly",
      "draxuvo_pro_weekly",
      "grupo_bothi_pro_monthly",
      "draxuvo_pro_monthly_extra",
      "xdraxuvo_pro_monthly",
      "DRAXUVO_PRO_MONTHLY"
    ].each do |value|
      assert_nil Plan.parse_lookup_key(value), "expected nil for #{value.inspect}"
    end
  end

  test "modules per plan match the catalog" do
    EXPECTED_MODULES.each do |key, modules|
      assert_equal modules, Plan.find(key).modules, "#{key}"
    end
  end

  test "every plan module belongs to MODULES" do
    Plan.all.each do |plan|
      assert_empty plan.modules - Plan::MODULES, "#{plan.key}"
    end
  end

  test "includes? reflects the plan modules" do
    basic = Plan.find(:basic)
    assert basic.includes?(:inventory)
    assert_not basic.includes?(:work_orders)
    assert_not basic.includes?(:whatsapp)

    pro = Plan.find(:pro)
    assert pro.includes?(:reports)
    assert_not pro.includes?(:whatsapp)
    assert_not pro.includes?(:multi_company)

    enterprise = Plan.find(:enterprise)
    Plan::MODULES.each { |mod| assert enterprise.includes?(mod), "enterprise should include #{mod}" }
  end

  test "includes? accepts strings and rejects unknown modules" do
    assert Plan.find(:pro).includes?("tickets")
    assert_not Plan.find(:enterprise).includes?(:payroll)
  end

  private

  def normalize(pair)
    pair&.map { |value| value.to_s.to_sym }
  end
end
