require "test_helper"

# Spec 058: la regla común de «Cobro solo por jefes».
class ChargePolicyTest < ActiveSupport::TestCase
  setup { @company = companies(:pos_co) }

  test "with the option off nobody is restricted" do
    %w[staff admin owner super_admin].each do |role|
      assert_not ChargePolicy.restricted?(@company, role), role
    end
  end

  test "with the option on only staff is restricted" do
    @company.update!(boss_only_charge: true)

    assert ChargePolicy.restricted?(@company, "staff")
    %w[admin owner super_admin].each do |role|
      assert_not ChargePolicy.restricted?(@company, role), role
    end
  end

  test "forbid! answers 403 with its own code" do
    error = assert_raises(ApiErrors::ForbiddenError) { ChargePolicy.forbid! }
    assert_equal "charge_boss_only", error.details[:code]
  end
end
