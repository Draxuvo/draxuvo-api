require "test_helper"

class Push::KindsTest < ActiveSupport::TestCase
  test "staff only gets the kinds about their own work" do
    assert_equal %w[check_ready work_order_assigned], Push::Kinds.available_for("staff", companies(:resto_co))
  end

  test "bosses also get operational alerts and low stock, following the active modules" do
    kinds = Push::Kinds.available_for("admin", companies(:resto_co))
    assert_includes kinds, "operational_alert"
    assert_includes kinds, "low_stock"
    assert_includes kinds, "check_ready"
  end

  test "a kind whose module is off is not offered" do
    company = companies(:basic_co)
    assert_not_includes Push::Kinds.available_for("owner", company), "check_ready"
    assert_not_includes Push::Kinds.available_for("owner", company), "work_order_assigned"
  end
end
