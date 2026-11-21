# Registra un pago y, si cubre la cuenta, la cierra en la misma transacción (FR-021 a FR-024, FR-027).
module Restaurant
  class AddPayment
    METHODS = %w[cash card transfer].freeze
    Result = Struct.new(:payment, :close, keyword_init: true)

    # `terminal_payment` (spec 069): el abono con tarjeta en una terminal integrada, armado por el servidor.
    def self.call(check, context, params, terminal_payment = nil) = new(check, context, params, terminal_payment).call

    def initialize(check, context, params, terminal_payment = nil)
      @terminal_payment = terminal_payment
      @check = check
      @context = context
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.with_indifferent_access : params.to_h.with_indifferent_access
    end

    def call
      Check.transaction do
        @check.lock!
        fail!(:check_not_open) unless @check.status_open?
        # Spec 069: con un abono esperando en la terminal no se registran otros pagos (el propio abono sí).
        TerminalCharge.ensure_none_open!(@check) unless @terminal_payment
        ChargePolicy.forbid! if @context.restricted? # spec 058: el personal no cobra
        raise ApiErrors::ForbiddenError.new(message: I18n.t("auth.not_authorized")) unless Permissions.pay?(@check, @context)

        method = @terminal_payment ? "card" : @params[:method].to_s
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("ticket.invalid_payment_method")) unless METHODS.include?(method)

        balance = @check.balance
        fail!(:invalid_amount) unless balance.positive?
        confirm_incomplete!

        attrs = @terminal_payment ? terminal_attributes_for(balance) : attributes_for(method, balance)
        payment = @check.check_payments.create!(attrs.merge(company: @check.company, created_by: @context.user))
        close = @check.balance.positive? ? nil : CloseCheck.call(@check, @context.user)
        Result.new(payment: payment, close: close)
      end
    end

    private

    # Con artículos sin entregar se pide confirmar antes de cobrar (FR-027).
    def confirm_incomplete!
      pending = @check.check_items.where(status: %i[new preparing ready]).count
      return if pending.zero? || ActiveModel::Type::Boolean.new.cast(@params[:confirm_incomplete])

      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("restaurant.errors.incomplete_items"), details: { code: "incomplete_items", pending: pending }
      )
    end

    def attributes_for(method, balance)
      method == "cash" ? cash_attributes(balance) : transfer_attributes(method, balance)
    end

    # En efectivo el monto abonado nunca pasa del saldo; lo que sobra del recibido es el cambio.
    def cash_attributes(balance)
      given = decimal(@params[:amount])
      received = decimal(@params[:amount_received]) || given
      fail!(:invalid_amount) if received.nil? || !received.positive?

      amount = [ given || received, balance ].min
      fail!(:invalid_amount) if received < amount
      { payment_method: :cash, amount: amount, amount_received: received }
    end

    # Transferencia y tarjeta: la transferencia exige referencia; la tarjeta la guarda si viene (spec 054, H-51), igual que
    # en el cobro de una orden de trabajo.
    def transfer_attributes(method, balance)
      amount = decimal(@params[:amount])
      fail!(:invalid_amount) if amount.nil? || !amount.positive?
      fail!(:exceeds_balance) if amount > balance
      reference = @params[:reference].to_s.strip
      fail!(:reference_required) if method == "transfer" && reference.empty?

      { payment_method: method, amount: amount, reference: reference.presence }.merge(terminal_attributes(method))
    end

    # El abono de una terminal integrada (spec 069): monto y terminal los fijó la solicitud; nunca pasa del saldo.
    def terminal_attributes_for(balance)
      tp = @terminal_payment
      amount = tp[:amount].to_d
      fail!(:invalid_amount) unless amount.positive?
      fail!(:exceeds_balance) if amount > balance

      { payment_method: "card", amount: amount, terminal: tp[:terminal], source: tp[:source] || :manual,
        terminal_charge: tp[:terminal_charge], reference: tp[:reference].presence }.compact
    end

    # La terminal en que se cobró con tarjeta, opcional (spec 015, FR-022).
    def terminal_attributes(method)
      return {} unless method == "card" && @params[:terminal_id].present?
      # Sin el módulo Terminales el cobro no se frena: la terminal se ignora (spec 030).
      return {} unless @check.company.module_active?(:terminals)

      terminal = PaymentTerminal.usable_for(@check.company, @params[:terminal_id])
      fail!(:invalid_terminal) unless terminal
      { terminal: terminal }
    end

    def decimal(value)
      return nil if value.to_s.strip.empty?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def fail!(code)
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("restaurant.errors.#{code}"), details: { code: code.to_s }
      )
    end
  end
end
