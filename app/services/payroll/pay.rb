module Payroll
  # Marca líneas como pagadas (spec 037, FR-011 y FR-012). Una línea o varias, todo o nada. Registrar un pago no mueve
  # dinero: el método y la referencia son solo informativos (FR-023).
  class Pay
    def self.call(**args) = new(**args).call

    # `payments`: nil = todas las pendientes de la corrida.
    def initialize(run:, user:, payment_method:, paid_on:, reference: nil, payments: nil)
      @run = run
      @user = user
      @method = payment_method.to_s
      @paid_on = paid_on
      @reference = reference.presence
      @payments = payments
    end

    def call
      validate_input!
      ActiveRecord::Base.transaction do
        run = PayrollRun.lock.find(@run.id)
        raise Error.new(:run_not_approved) unless run.approved? || run.partial?

        selected = selected_payments(run)
        pending = selected.select(&:pending?)
        # Reintento de lo mismo: la línea ya está pagada con estos datos, no hay nada que repetir.
        return finish(run, []) if pending.empty? && selected.all? { |p| same_payment?(p) } && selected.any?
        raise Error.new(:already_paid) if selected.any? { |p| p.paid? && !same_payment?(p) }
        raise Error.new(:nothing_to_pay) if pending.empty?

        pending.each do |payment|
          payment.update!(status: :paid, payment_method: @method, reference: @reference, paid_on: @paid_on,
                          paid_by: @user, paid_at: Time.current)
        end
        status = run.payments.pending.exists? ? :partial : :paid
        run.update!(status: status)
        RecordEvent.call(run: run, user: @user, action: :paid,
                         details: { payment_ids: pending.map(&:id), payment_method: @method, paid_on: @paid_on,
                                    total_cents: pending.sum(&:net_cents) })
        finish(run, pending)
      end
    end

    private

    def validate_input!
      raise Error.new(:invalid_method) unless PayrollPayment.payment_methods.key?(@method)
      raise Error.new(:future_date) if @paid_on.blank? || @paid_on > Time.zone.today
      raise Error.new(:reference_too_long) if @reference.to_s.length > 80
    end

    def selected_payments(run)
      return run.payments.pending.order(:employee_name).to_a if @payments.nil?

      list = run.payments.where(id: @payments).order(:employee_name).to_a
      raise ActiveRecord::RecordNotFound if list.size != @payments.uniq.size

      list
    end

    def same_payment?(payment)
      payment.paid? && payment.payment_method == @method && payment.paid_on == @paid_on &&
        payment.reference.to_s == @reference.to_s
    end

    def finish(run, paid) = [ run.reload, paid ]
  end
end
