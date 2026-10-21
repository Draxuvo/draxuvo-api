require "test_helper"

# Reglas del cobro con varios pagos (spec 015, research R4).
class WorkOrders::ChargePaymentsTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @total = BigDecimal("500")
  end

  def split(payments)
    WorkOrders::ChargePayments.call(@company, @total, { payments: payments })
  end

  def error_code(payments)
    error = assert_raises(ApiErrors::UnprocessableEntityError) { split(payments) }
    error.details[:code]
  end

  test "card plus cash: the cash covers the rest and gives change" do
    result = split([ { method: "card", amount: "300", terminal_id: payment_terminals(:pro_bbva).id, authorization_code: "123456", card_last4: "4242" },
                     { method: "cash", amount_received: "250" } ])
    assert_equal "mixed", result.payment_method
    cash = result.payments.find { |p| p[:payment_method] == :cash }
    assert_equal BigDecimal("200"), cash[:amount]
    assert_equal BigDecimal("50"), result.change_given
    assert_equal BigDecimal("550"), result.amount_received
    card = result.payments.find { |p| p[:payment_method] == :card }
    assert_equal payment_terminals(:pro_bbva), card[:terminal]
    assert_equal "4242", card[:card_last4]
  end

  test "a single card for the exact total keeps the card method, with or without authorization" do
    result = split([ { method: "card", amount: "500" } ])
    assert_equal "card", result.payment_method
    assert_equal BigDecimal("0"), result.change_given
    assert_nil result.payments.first[:authorization_code]
  end

  test "payments that do not cover the total report what is missing" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) { split([ { method: "card", amount: "300" } ]) }
    assert_equal({ code: "missing", missing: "200.0" }, error.details)
    assert_equal "missing", error_code([ { method: "card", amount: "300" }, { method: "cash", amount_received: "100" } ])
  end

  test "rejects each invalid case with its code" do
    assert_equal "exceeds_total", error_code([ { method: "card", amount: "600" } ])
    assert_equal "multiple_cash", error_code([ { method: "cash", amount_received: "100" }, { method: "cash", amount_received: "400" } ])
    assert_equal "reference_required", error_code([ { method: "transfer", amount: "500" } ])
    assert_equal "invalid_amount", error_code([ { method: "card", amount: "0" } ])
    assert_equal "invalid_card_last4", error_code([ { method: "card", amount: "500", card_last4: "12" } ])
    assert_equal "invalid_terminal", error_code([ { method: "card", amount: "500", terminal_id: payment_terminals(:pro_clip_off).id } ])
    assert_equal "invalid_terminal", error_code([ { method: "card", amount: "500", terminal_id: payment_terminals(:resto_point).id } ])
    assert_equal "too_many_payments", error_code(Array.new(6) { { method: "card", amount: "1" } })
    assert_equal "invalid_amount", error_code([ { method: "card", amount: "500" }, { method: "cash", amount_received: "10" } ])
  end

  test "the invalid index points at the bad payment" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      split([ { method: "cash", amount_received: "100" }, { method: "transfer", amount: "100" } ])
    end
    assert_equal 1, error.details[:index]
  end

  test "the previous format becomes a single payment" do
    card = WorkOrders::ChargePayments.call(@company, @total, { payment_method: "card", amount_received: "1" })
    assert_equal [ BigDecimal("500") ], card.payments.map { |p| p[:amount] }
    cash = WorkOrders::ChargePayments.call(@company, @total, { payment_method: "cash", amount_received: "1000" })
    assert_equal BigDecimal("500"), cash.change_given
    transfer = WorkOrders::ChargePayments.call(@company, @total, { payment_method: "transfer" })
    assert_equal "transfer", transfer.payment_method
  end

  # --- spec 030: sin el módulo Terminales el cobro no se frena ---

  test "with the terminals module off a card payment is saved without terminal and without error" do
    @company.update!(disabled_modules: %w[terminals])

    result = split([ { method: "card", amount: "500", terminal_id: payment_terminals(:pro_bbva).id } ])

    card = result.payments.find { |p| p[:payment_method] == :card }
    assert_nil card[:terminal]
    assert_equal BigDecimal("500"), card[:amount]
  end

  test "with the terminals module off even an invalid terminal does not fail the charge" do
    @company.update!(disabled_modules: %w[terminals])

    result = split([ { method: "card", amount: "500", terminal_id: payment_terminals(:resto_point).id } ])

    assert_nil result.payments.first[:terminal]
  end
end
