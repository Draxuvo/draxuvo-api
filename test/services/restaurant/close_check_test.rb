require "test_helper"

class Restaurant::CloseCheckTest < ActiveSupport::TestCase
  setup { @user = users(:resto_owner) }

  test "closes a check without payments in zero as a courtesy with the reason" do
    check = checks(:takeout_check)
    result = Restaurant::CloseCheck.call(check, @user, reason: "Cortesía de la casa")

    assert result.ticket.persisted?
    assert_equal 0, result.ticket.total
    assert_equal "Cortesía de la casa", result.ticket.notes
    assert check.reload.status_closed?
    assert check.closed_at.present?
  end

  test "the ticket belongs to the check and takes the folio format" do
    check = settle_check(checks(:open_check))
    check.check_payments.create!(company: check.company, created_by: @user, payment_method: :card, amount: check.total, reference: "A1")

    ticket = Restaurant::CloseCheck.call(check, @user).ticket

    assert_equal check, ticket.check
    assert_match(/\AT-\d{6,}\z/, ticket.folio)
    assert_equal "card", ticket.payment_method
    assert_equal @user, ticket.charged_by
  end

  test "a courtesy closing with a paid-free check deducts stock for what was served" do
    check = checks(:takeout_check)
    check.check_items.create!(company: check.company, product: products(:resto_tacos), name: "Tacos", unit_price: 0, quantity: 2)
      .update!(status: :new, kitchen_order: kitchen_orders(:first_round))

    assert_difference -> { products(:resto_tacos).reload.stock }, -2 do
      Restaurant::CloseCheck.call(check, @user, reason: "x")
    end
  end
end
