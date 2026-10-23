# Corrida de nómina (spec 037). Con `detail` trae las líneas y la bitácora.
class PayrollRunSerializer
  def initialize(run, detail: false)
    @run = run
    @detail = detail
  end

  def as_json(*)
    r = @run
    payments = r.payments.to_a
    json = {
      id: r.id, period_type: r.period_type, starts_on: r.starts_on, ends_on: r.ends_on, status: r.status,
      total_cents: r.total_cents, lock_version: r.lock_version, payments_count: payments.size,
      paid_count: payments.count(&:paid?), paid_cents: payments.select(&:paid?).sum(&:net_cents),
      created_by: user_ref(r.created_by), approved_by: user_ref(r.approved_by), approved_at: r.approved_at,
      cancelled_at: r.cancelled_at, cancel_reason: r.cancel_reason, created_at: r.created_at
    }
    if @detail
      json[:payments] = payments.sort_by(&:employee_name).map { |p| PayrollPaymentSerializer.new(p).as_json }
      json[:events] = r.events.includes(:user).order(:created_at, :id).map { |e| PayrollEventSerializer.new(e).as_json }
    end
    json
  end

  private

  def user_ref(user) = user && { id: user.id, name: user.full_name }
end
