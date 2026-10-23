module Payroll
  # Crea una corrida en borrador con una línea por empleado activo (spec 037, US1).
  class BuildRun
    def self.call(**args) = new(**args).call

    def initialize(company:, user:, period_type:, starts_on:, ends_on:)
      @company = company
      @user = user
      @period_type = period_type.to_s
      @starts_on = starts_on
      @ends_on = ends_on
    end

    def call
      ActiveRecord::Base.transaction do
        # Serializa las altas de corridas de la misma empresa para que el empalme no se cuele (R5).
        @company.lock!
        raise Error.new(:period_invalid) unless PayrollRun.period_types.key?(@period_type)

        run = @company.payroll_runs.new(period_type: @period_type, starts_on: @starts_on, ends_on: @ends_on,
                                        created_by: @user)
        raise Error.new(:period_invalid) unless run.valid?

        check_overlap!
        run.save!
        raise Error.new(:no_employees) if Lines.new(run).add_missing!.zero?

        Recalculate.run!(run)
        RecordEvent.call(run: run, user: @user, action: :created,
                         details: { period_type: @period_type, starts_on: @starts_on, ends_on: @ends_on })
        run
      end
    end

    private

    def check_overlap!
      other = @company.payroll_runs.where.not(status: :cancelled)
                      .where("starts_on <= ? AND ends_on >= ?", @ends_on, @starts_on).first
      return unless other

      raise Error.new(:period_overlap, status: :conflict,
                      details: { run_id: other.id, starts_on: other.starts_on, ends_on: other.ends_on })
    end
  end
end
