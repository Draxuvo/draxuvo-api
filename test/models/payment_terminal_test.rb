require "test_helper"

class PaymentTerminalTest < ActiveSupport::TestCase
  test "name is unique per company ignoring case" do
    dup = companies(:pro_co).payment_terminals.build(name: "  bbva CAJA 1 ", provider: "bbva")
    assert_not dup.valid?
    assert dup.errors.added?(:name, :taken, value: "bbva CAJA 1")

    assert companies(:resto_co).payment_terminals.build(name: "BBVA caja 1", provider: "bbva").valid?
  end

  test "provider must be in the list" do
    terminal = companies(:pro_co).payment_terminals.build(name: "Otra", provider: "paypal")
    assert_not terminal.valid?
    assert terminal.errors.key?(:provider)
  end

  test "a terminal with payments cannot be destroyed" do
    terminal = payment_terminals(:pro_bbva)
    assert_equal 1, terminal.payments_count
    assert_not terminal.destroy
    assert PaymentTerminal.exists?(terminal.id)

    assert payment_terminals(:pro_clip_off).destroy
  end
end
