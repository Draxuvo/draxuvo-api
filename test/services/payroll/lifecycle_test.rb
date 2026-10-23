require "test_helper"

class Payroll::LifecycleTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @ana, @beto = payroll_employees(@company, { name: "Ana", salary: 12_000 }, { name: "Beto", salary: 9_000 })
    @run = build_payroll_run(@company, @owner)
    @ana_line = @run.payments.find_by!(employee: @ana)
  end

  def adjust(payment, kind, cents, note = "Nota", **extra)
    payment.adjustments.create!(company: @company, kind: kind, amount_cents: cents, note: note, created_by: @owner, **extra)
    Payroll::Recalculate.payment!(payment.reload)
  end

  test "net is salary plus bonuses minus deductions and the run total adds the nets" do
    adjust(@ana_line, :bonus, 50_000, "Puntualidad")
    adjust(@ana_line, :deduction, 20_000, "Anticipo")

    assert_equal [ 600_000, 50_000, 20_000, 630_000 ], @ana_line.reload.attributes.values_at("salary_cents", "bonus_cents", "deduction_cents", "net_cents")
    assert_equal 630_000 + 450_000, @run.reload.total_cents
  end

  test "adjustments need a positive amount and a note" do
    bad = @ana_line.adjustments.new(company: @company, kind: :bonus, amount_cents: 0, note: "", created_by: @owner)
    assert_not bad.valid?
    assert_includes bad.errors.attribute_names, :amount_cents
    assert_includes bad.errors.attribute_names, :note
  end

  test "days to pay prorate the salary" do
    @ana_line.update!(days_paid: 8)
    Payroll::Recalculate.payment!(@ana_line)
    assert_equal 320_000, @ana_line.reload.net_cents

    @ana_line.days_paid = 16
    assert_not @ana_line.valid?
  end

  test "approving freezes the run and records who and when" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)

    assert run.approved?
    assert_equal [ @owner.id, true ], [ run.approved_by_id, run.approved_at.present? ]
    assert_equal %w[created approved], run.events.order(:id).pluck(:action)
  end

  test "approving with a stale lock_version raises a conflict" do
    stale = @run.reload.lock_version
    adjust(@ana_line, :bonus, 100, "Después")

    error = assert_raises(Payroll::Error) { Payroll::Approve.call(run: @run, user: @owner, lock_version: stale) }
    assert_equal [ :stale_object, :conflict ], [ error.code, error.status ]
    assert @run.reload.draft?
  end

  test "approving lists the lines whose net is zero or negative" do
    adjust(@ana_line, :deduction, 700_000, "Demasiado")

    error = assert_raises(Payroll::Error) { Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version) }
    assert_equal [ :lines_invalid, [ @ana_line.id ] ], [ error.code, error.details[:payment_ids] ]
  end

  test "pays one line, then the rest in a batch, moving the run through partial to paid" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)

    Payroll::Pay.call(run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.today, payments: [ @ana_line.id ])
    assert run.reload.partial?
    assert_equal [ "paid", "cash", @owner.id ], @ana_line.reload.attributes.values_at("status", "payment_method", "paid_by_id")

    Payroll::Pay.call(run: run, user: @owner, payment_method: "transfer", paid_on: Time.zone.today, reference: "SPEI 123")
    assert run.reload.paid?
    assert_equal [ "transfer", "SPEI 123" ], run.payments.find_by!(employee: @beto).attributes.values_at("payment_method", "reference")
  end

  test "repeating the same payment changes nothing and a different one is rejected" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    args = { run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.today, payments: [ @ana_line.id ] }
    Payroll::Pay.call(**args)

    assert_no_difference -> { PayrollEvent.count } do
      Payroll::Pay.call(**args)
    end
    error = assert_raises(Payroll::Error) { Payroll::Pay.call(**args, payment_method: "transfer") }
    assert_equal :already_paid, error.code
  end

  test "rejects future dates, unknown methods and unapproved runs" do
    assert_equal :run_not_approved, assert_raises(Payroll::Error) { Payroll::Pay.call(run: @run, user: @owner, payment_method: "cash", paid_on: Time.zone.today) }.code
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    assert_equal :future_date, assert_raises(Payroll::Error) { Payroll::Pay.call(run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.tomorrow) }.code
    assert_equal :invalid_method, assert_raises(Payroll::Error) { Payroll::Pay.call(run: run, user: @owner, payment_method: "bitcoin", paid_on: Time.zone.today) }.code
  end

  test "a batch is all or nothing" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)

    assert_raises(ActiveRecord::RecordNotFound) do
      Payroll::Pay.call(run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.today, payments: [ @ana_line.id, 0 ])
    end
    assert_equal 2, run.payments.pending.count
  end

  test "a paid line cannot be changed or deleted" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    Payroll::Pay.call(run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.today, payments: [ @ana_line.id ])
    line = @ana_line.reload

    assert_not line.update(net_cents: 1)
    assert_not line.update(payment_method: "transfer")
    assert_not line.destroy
    assert_equal 600_000, line.reload.net_cents
  end

  test "cancelling needs a reason and no payments" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    assert_equal :reason_required, assert_raises(Payroll::Error) { Payroll::Cancel.call(run: run, user: @owner, reason: " ") }.code

    Payroll::Pay.call(run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.today, payments: [ @ana_line.id ])
    assert_equal :has_payments, assert_raises(Payroll::Error) { Payroll::Cancel.call(run: run, user: @owner, reason: "Error") }.code
  end

  test "cancelling an approved run without payments records the reason" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    Payroll::Cancel.call(run: run, user: @owner, reason: "Periodo equivocado")

    assert run.reload.cancelled?
    assert_equal [ "Periodo equivocado", @owner.id ], [ run.cancel_reason, run.cancelled_by_id ]
  end

  test "a correction adjustment points at a paid line of the same employee" do
    run = Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    Payroll::Pay.call(run: run, user: @owner, payment_method: "cash", paid_on: Time.zone.today, payments: [ @ana_line.id ])
    next_run = build_payroll_run(@company, @owner, starts_on: Date.new(2026, 10, 16), ends_on: Date.new(2026, 10, 31))
    ana_next = next_run.payments.find_by!(employee: @ana)

    adjust(ana_next, :bonus, 10_000, "Corrige pago anterior", corrects_payment: @ana_line.reload)
    assert_equal 610_000, ana_next.reload.net_cents

    wrong = next_run.payments.find_by!(employee: @beto).adjustments.new(company: @company, kind: :bonus, amount_cents: 1, note: "x",
                                                                         created_by: @owner, corrects_payment: @ana_line)
    assert_not wrong.valid?
  end

  test "adjustments are locked once the run is approved" do
    Payroll::Approve.call(run: @run, user: @owner, lock_version: @run.reload.lock_version)
    late = @ana_line.reload.adjustments.new(company: @company, kind: :bonus, amount_cents: 1, note: "tarde", created_by: @owner)
    assert_not late.valid?
  end

  test "csv has one row per employee plus the total and a BOM" do
    adjust(@ana_line, :bonus, 50_000, "Bono")
    csv = Payroll::CsvExport.call(@run.reload)

    assert csv.start_with?("﻿")
    rows = CSV.parse(csv.delete_prefix("﻿"))
    assert_equal 4, rows.size
    assert_equal [ "Ana", "12000.00", "15", "15", "6000.00", "500.00", "0.00", "6500.00" ], rows[1].first(8)
    assert_equal "11000.00", rows.last[7]
  end
end
