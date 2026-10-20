require "test_helper"

class TicketPaymentTest < ActiveSupport::TestCase
  def build(**attrs)
    TicketPayment.new({ company: companies(:pro_co), ticket: tickets(:pro_paid_ticket),
                        created_by: users(:pro_co_owner) }.merge(attrs))
  end

  test "cash computes the change" do
    payment = build(payment_method: :cash, amount: 200, amount_received: 500)
    assert payment.valid?
    assert_equal 300, payment.change_given
  end

  test "cash received below the amount is invalid" do
    assert_not build(payment_method: :cash, amount: 200, amount_received: 100).valid?
  end

  test "transfer requires a reference" do
    assert_not build(payment_method: :transfer, amount: 100).valid?
    assert build(payment_method: :transfer, amount: 100, reference: "SPEI 1").valid?
  end

  test "card accepts optional authorization and last 4 digits" do
    assert build(payment_method: :card, amount: 100).valid?
    assert build(payment_method: :card, amount: 100, authorization_code: "A12345", card_last4: "4242").valid?
    assert_not build(payment_method: :card, amount: 100, card_last4: "42a2").valid?
  end

  test "terminal must belong to the company and be active" do
    assert build(payment_method: :card, amount: 100, terminal: payment_terminals(:pro_bbva)).valid?
    assert_not build(payment_method: :card, amount: 100, terminal: payment_terminals(:pro_clip_off)).valid?
    assert_not build(payment_method: :card, amount: 100, terminal: payment_terminals(:resto_point)).valid?
  end

  test "card fields are rejected on other methods" do
    assert_not build(payment_method: :cash, amount: 100, terminal: payment_terminals(:pro_bbva)).valid?
  end

  test "a saved payment only changes voided_at" do
    payment = ticket_payments(:pro_paid_card)
    assert_raises(ActiveRecord::ReadOnlyRecord) { payment.update!(amount: 1) }
    payment.reload.update!(voided_at: Time.current)
    assert payment.reload.voided_at
  end
end
