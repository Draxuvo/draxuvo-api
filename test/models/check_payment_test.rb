require "test_helper"

class CheckPaymentTest < ActiveSupport::TestCase
  setup do
    @check = checks(:open_check)
    @check.recalculate_total!
    @user = users(:resto_waiter)
  end

  def pay(**attrs)
    @check.check_payments.build({ company: @check.company, created_by: @user }.merge(attrs))
  end

  test "card and transfer need a reference" do
    assert_not pay(payment_method: :card, amount: 50).valid?
    assert_not pay(payment_method: :transfer, amount: 50).valid?
    assert pay(payment_method: :card, amount: 50, reference: "A1").valid?
  end

  test "cash does not need a reference and computes the change" do
    payment = pay(payment_method: :cash, amount: 100, amount_received: 200)
    assert payment.valid?
    assert_equal 100, payment.change_given
  end

  test "cash received defaults to the amount" do
    payment = pay(payment_method: :cash, amount: 100)
    payment.valid?

    assert_equal 100, payment.amount_received
    assert_equal 0, payment.change_given
  end

  test "cash received cannot be less than the amount" do
    assert_not pay(payment_method: :cash, amount: 100, amount_received: 50).valid?
  end

  test "a payment cannot exceed the balance" do
    balance = @check.balance

    assert_not pay(payment_method: :card, amount: balance + 1, reference: "A1").valid?
    assert pay(payment_method: :card, amount: balance, reference: "A1").valid?
  end

  test "amount must be positive" do
    assert_not pay(payment_method: :cash, amount: 0).valid?
  end

  test "a saved payment is read only" do
    saved = pay(payment_method: :cash, amount: 10)
    saved.save!

    assert_raises(ActiveRecord::ReadOnlyRecord) { saved.update!(amount: 5) }
  end
end
