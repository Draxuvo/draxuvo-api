module Payroll
  # Aprueba una corrida: congela los montos (spec 037, FR-010). Se rechaza si la corrida cambió desde que el jefe la
  # vio (`lock_version`) o si alguna línea queda en cero o negativa.
  class Approve
    def self.call(**args) = new(**args).call

    def initialize(run:, user:, lock_version:)
      @run = run
      @user = user
      @lock_version = lock_version
    end

    def call
      ActiveRecord::Base.transaction do
        run = PayrollRun.lock.find(@run.id)
        raise Error.new(:not_draft) unless run.draft?
        raise Error.new(:stale_object, status: :conflict) unless @lock_version.present? && run.lock_version == @lock_version.to_i

        invalid = run.payments.where(net_cents: ..0)
        if invalid.exists?
          raise Error.new(:lines_invalid, details: { payment_ids: invalid.order(:employee_name).pluck(:id) })
        end
        raise Error.new(:empty_run) unless run.payments.exists?

        run.update!(status: :approved, approved_by: @user, approved_at: Time.current)
        RecordEvent.call(run: run, user: @user, action: :approved, details: { total_cents: run.total_cents })
        run
      end
    end
  end
end
