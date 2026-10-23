require "test_helper"

class Payroll::PeriodTest < ActiveSupport::TestCase
  test "counts calendar days with both ends included" do
    assert_equal 15, Payroll::Period.days(Date.new(2026, 10, 1), Date.new(2026, 10, 15))
    assert_equal 1, Payroll::Period.days(Date.new(2026, 10, 1), Date.new(2026, 10, 1))
  end

  test "splits the monthly salary by period type" do
    assert_equal 1_200_000, Payroll::Period.period_salary_cents(1_200_000, :monthly)
    assert_equal 600_000, Payroll::Period.period_salary_cents(1_200_000, :biweekly)
    assert_equal 276_923, Payroll::Period.period_salary_cents(1_200_000, :weekly) # 12/52, half-up
  end

  test "prorates the line by days to pay, rounding once" do
    assert_equal 320_000, Payroll::Period.line_salary_cents(1_200_000, :biweekly, 8, 15)
    assert_equal 0, Payroll::Period.line_salary_cents(1_200_000, :biweekly, 0, 15)
    assert_equal 600_000, Payroll::Period.line_salary_cents(1_200_000, :biweekly, 15, 15)
  end

  test "converts the decimal salary in pesos to cents" do
    assert_equal 1_234_550, Payroll::Period.salary_to_cents(BigDecimal("12345.5"))
    assert_equal 0, Payroll::Period.salary_to_cents(nil)
  end
end
