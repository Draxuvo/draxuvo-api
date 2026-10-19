require "test_helper"

class TicketTest < ActiveSupport::TestCase
  def build_ticket(**attrs)
    Ticket.new({ work_order: work_orders(:pro_done), company: companies(:pro_co), total: 850 }.merge(attrs))
  end

  def paid_attrs(**extra)
    { status: :paid, payment_method: :cash, amount_received: 900, charged_by: users(:pro_co_owner),
      paid_at: Time.current }.merge(extra)
  end

  test "a new ticket is pending and valid" do
    ticket = build_ticket
    assert ticket.pending?
    assert ticket.valid?
  end

  test "creating assigns a folio T-%06d from the id" do
    ticket = build_ticket.tap(&:save!)
    assert_equal format("T-%06d", ticket.id), ticket.reload.folio
  end

  test "total is required and not negative" do
    assert_not build_ticket(total: nil).valid?
    assert_not build_ticket(total: -1).valid?
    assert build_ticket(total: 0).valid?
  end

  test "folio is unique" do
    duplicate = build_ticket(work_order: work_orders(:pro_open))
    duplicate.save!
    clash = build_ticket(work_order: work_orders(:pro_started))
    clash.save!
    clash.folio = duplicate.reload.folio
    assert_not clash.valid?
    assert clash.errors[:folio].any?
  end

  test "a paid ticket needs method, amount, who charged and date" do
    ticket = build_ticket(status: :paid)
    assert_not ticket.valid?
    %i[payment_method amount_received charged_by paid_at].each { |attr| assert ticket.errors[attr].any?, attr.to_s }
    assert build_ticket(**paid_attrs).valid?
  end

  test "the amount received cannot be below the total" do
    ticket = build_ticket(**paid_attrs(amount_received: 800))
    assert_not ticket.valid?
    assert ticket.errors[:amount_received].any?
    assert build_ticket(**paid_attrs(amount_received: 850)).valid?
  end

  test "a voided ticket needs date, who and reason" do
    ticket = build_ticket(status: :voided)
    assert_not ticket.valid?
    %i[voided_at voided_by void_reason].each { |attr| assert ticket.errors[attr].any?, attr.to_s }
    ok = build_ticket(status: :voided, voided_at: Time.current, voided_by: users(:pro_co_owner),
                      void_reason: "Error de captura")
    assert ok.valid?
  end

  test "enums expose statuses and payment methods" do
    assert_equal({ "pending" => 0, "paid" => 1, "voided" => 2 }, Ticket.statuses)
    assert_equal({ "cash" => 0, "card" => 1, "transfer" => 2, "mixed" => 3 }, Ticket.payment_methods)
    assert_nil build_ticket.payment_method
    assert_raises(ArgumentError) { build_ticket(payment_method: :bitcoin) }
  end

  test "status_label_text is translated" do
    assert_equal "Pagado", tickets(:pro_paid_ticket).status_label_text
    I18n.with_locale(:en) { assert_equal "Pending payment", build_ticket.status_label_text }
  end

  test "an order has a single ticket" do
    build_ticket.save!
    assert_raises(ActiveRecord::RecordNotUnique) { build_ticket.save! }
  end

  test "destroying the order removes its ticket" do
    assert_difference -> { Ticket.count }, -1 do
      work_orders(:pro_paid).update_columns(status: WorkOrder.statuses[:done])
      work_orders(:pro_paid).destroy!
    end
  end

  test "a ticket belongs to exactly one of a work order or a check" do
    paid = tickets(:resto_paid_ticket)
    assert paid.valid?

    paid.work_order = work_orders(:pro_paid)
    assert_not paid.valid?, "no puede tener orden y cuenta a la vez"

    paid.work_order = nil
    paid.check = nil
    assert_not paid.valid?, "tampoco ninguno de los dos"
  end

  test "a mixed ticket is a valid payment method for a check" do
    paid = tickets(:resto_paid_ticket)
    paid.payment_method = :mixed

    assert paid.valid?
  end
end
