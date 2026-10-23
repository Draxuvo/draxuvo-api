# Bono o deducción de una línea de nómina (spec 037).
class PayrollAdjustmentSerializer
  def initialize(adjustment)
    @adjustment = adjustment
  end

  def as_json(*)
    a = @adjustment
    { id: a.id, payroll_payment_id: a.payroll_payment_id, kind: a.kind, amount_cents: a.amount_cents, note: a.note,
      corrects_payment_id: a.corrects_payment_id,
      created_by: a.created_by && { id: a.created_by.id, name: a.created_by.full_name }, created_at: a.created_at }
  end
end
