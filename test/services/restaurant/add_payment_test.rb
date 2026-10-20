require "test_helper"

class Restaurant::AddPaymentTest < ActiveSupport::TestCase
  setup do
    @check = settle_check(checks(:open_check)) # total 155
    @waiter = Restaurant::Permissions::Context.new(user: users(:resto_waiter), role: "staff")
    @other = Restaurant::Permissions::Context.new(user: users(:resto_waiter2), role: "staff")
    @boss = Restaurant::Permissions::Context.new(user: users(:resto_manager), role: "manager")
  end

  def pay(params, context = @waiter, check = @check) = Restaurant::AddPayment.call(check, context, params)

  def code_of
    yield
    flunk "debía fallar"
  rescue ApiErrors::BaseError => e
    e.details.is_a?(Hash) ? e.details[:code] : e.class.name
  end

  test "cash above the balance closes the check and returns the change" do
    result = pay(method: "cash", amount_received: "200")

    assert_equal 155, result.payment.amount
    assert_equal 45, result.payment.change_given
    assert result.close.ticket.persisted?
    assert @check.reload.status_closed?
  end

  test "cash can pay only part of the check" do
    result = pay(method: "cash", amount: "55", amount_received: "100")

    assert_nil result.close
    assert @check.reload.status_open?
    assert_equal 100, @check.balance
  end

  test "mixed payments close the check once they cover it" do
    pay(method: "cash", amount: "55", amount_received: "100")
    pay(method: "card", amount: "50", reference: "A1")
    result = pay(method: "transfer", amount: "50", reference: "T9")

    assert result.close
    ticket = result.close.ticket
    assert_equal "mixed", ticket.payment_method
    assert_equal 155, ticket.total
    assert_equal 3, @check.check_payments.count
  end

  test "a single card payment keeps card as the ticket method" do
    result = pay(method: "card", amount: "155", reference: "A1")

    assert_equal "card", result.close.ticket.payment_method
  end

  test "card without a reference is rejected" do
    assert_equal "reference_required", code_of { pay(method: "card", amount: "50") }
    assert_equal "reference_required", code_of { pay(method: "transfer", amount: "50", reference: " ") }
  end

  test "card above the balance is rejected" do
    assert_equal "exceeds_balance", code_of { pay(method: "card", amount: "500", reference: "A1") }
    assert_equal 155, @check.reload.balance
  end

  test "an invalid method or amount is rejected" do
    assert_equal "ApiErrors::UnprocessableEntityError", code_of { pay(method: "bitcoin", amount: "50") }
    assert_equal "invalid_amount", code_of { pay(method: "card", amount: "0", reference: "A1") }
    assert_equal "invalid_amount", code_of { pay(method: "card", amount: "abc", reference: "A1") }
    assert_equal "invalid_amount", code_of { pay(method: "cash", amount: "100", amount_received: "50") }
  end

  test "items not delivered ask for confirmation first" do
    unsettle_open_check
    check = checks(:open_check) # tiene artículos nuevos, en preparación y listos
    error = assert_raises(ApiErrors::UnprocessableEntityError) { pay({ method: "cash", amount_received: "500" }, @waiter, check) }

    assert_equal "incomplete_items", error.details[:code]
    assert_equal 3, error.details[:pending]
    assert_equal 0, check.check_payments.count
  end

  test "confirming the incomplete items charges anyway" do
    unsettle_open_check
    check = checks(:open_check)

    result = pay({ method: "cash", amount_received: "500", confirm_incomplete: true }, @waiter, check)

    assert result.close
  end

  test "only the waiter of the check or a boss can charge" do
    assert_raises(ApiErrors::ForbiddenError) { pay({ method: "cash", amount_received: "200" }, @other) }
    assert pay({ method: "cash", amount_received: "200" }, @boss).close
  end

  test "a closed check does not take payments" do
    assert_equal "check_not_open", code_of { pay({ method: "cash", amount_received: "10" }, @waiter, checks(:closed_check)) }
  end

  test "the sale deducts tracked stock and writes the movement" do
    tacos = products(:resto_tacos)
    check = checks(:open_check)
    check.check_items.where(product: tacos).update_all(quantity: 3)
    settle_check(check)

    assert_difference -> { tacos.reload.stock }, -3 do
      pay({ method: "cash", amount_received: "500" }, @waiter, check)
    end
    movement = tacos.stock_movements.order(:id).last
    assert_equal [ "exit", 3 ], [ movement.movement_type, movement.qty ]
    assert_includes movement.note, check.id.to_s
  end

  test "stock never goes below zero and the close still happens" do
    cola = products(:resto_cola) # 2 en inventario
    check = checks(:open_check)
    check.check_items.where(product: cola).update_all(quantity: 5)
    settle_check(check)

    result = pay({ method: "cash", amount_received: "500" }, @waiter, check)

    assert result.close
    assert_equal 0, cola.reload.stock
    assert_equal [ { product_id: cola.id, missing: 3 } ], result.close.shortages
  end

  test "untracked products never touch inventory" do
    sopa = products(:resto_sopa)

    assert_no_difference -> { sopa.reload.stock } do
      pay(method: "cash", amount_received: "500")
    end
  end

  test "cancelled items are not charged or deducted" do
    tacos = products(:resto_tacos)
    unsettle_open_check
    check = checks(:open_check)
    check_items(:item_new).update!(status: :cancelled, cancelled_at: Time.current, cancel_reason: "x", cancelled_by: users(:resto_manager))
    settle_check(check)

    assert_equal 85, check.total
    assert_no_difference -> { tacos.reload.stock } do
      pay({ method: "cash", amount_received: "100" }, @waiter, check)
    end
  end

  test "the table is free again after closing" do
    pay(method: "cash", amount_received: "200")

    assert_not dining_tables(:table_1).occupied?
  end

  # --- spec 015: terminal en pagos con tarjeta ---

  test "a card payment keeps the chosen terminal and still requires a reference" do
    terminal = payment_terminals(:resto_point)
    result = pay(method: "card", amount: "50", reference: "A1", terminal_id: terminal.id)
    assert_equal terminal, result.payment.terminal
    assert_equal "manual", result.payment.source

    assert_equal "reference_required", code_of { pay(method: "card", amount: "50", terminal_id: terminal.id) }
  end

  test "a terminal of another company or inactive is rejected" do
    assert_equal "invalid_terminal", code_of { pay(method: "card", amount: "50", reference: "A1", terminal_id: payment_terminals(:pro_bbva).id) }
    payment_terminals(:resto_point).update!(active: false)
    assert_equal "invalid_terminal", code_of { pay(method: "card", amount: "50", reference: "A1", terminal_id: payment_terminals(:resto_point).id) }
    assert_equal 0, @check.check_payments.count
  end
end
