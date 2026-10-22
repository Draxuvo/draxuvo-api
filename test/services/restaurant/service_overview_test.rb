require "test_helper"

class Restaurant::ServiceOverviewTest < ActiveSupport::TestCase
  setup { @company = companies(:resto_co) }

  def overview(checks, counts)
    Restaurant::ServiceOverview.new(@company, checks, counts).call
  end

  test "counts open checks, pending comandas and the oldest minutes" do
    result = overview([ checks(:open_check), checks(:takeout_check) ],
                      checks(:open_check).id => { "new" => 1, "preparing" => 1, "ready" => 1 })

    assert_equal 2, result[:open_checks]
    assert_equal 2, result[:pending_comandas]
    assert_equal "0.00", result[:to_pay_total]
    assert_includes 19..21, result[:oldest_open_minutes]
  end

  test "adds the balance of the checks that are to pay" do
    check = checks(:open_check)
    result = overview([ check ], check.id => { "delivered" => 2 })

    assert_equal format("%.2f", check.balance), result[:to_pay_total]
    assert_equal 0, result[:pending_comandas]
  end

  test "without open checks the oldest is nil" do
    result = overview([], {})

    assert_equal 0, result[:open_checks]
    assert_nil result[:oldest_open_minutes]
  end
end
