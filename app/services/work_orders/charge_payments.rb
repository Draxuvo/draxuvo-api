# Reparte el cobro de una orden en sus pagos (spec 015, research R4). No guarda nada: valida la lista y
# devuelve los atributos de cada `TicketPayment` y del ticket. Tarjeta y transferencia llevan su monto y
# no pasan del total; el efectivo (a lo más uno) cubre el resto y su excedente es el cambio.
module WorkOrders
  class ChargePayments
    METHODS = %w[cash card transfer].freeze
    MAX_PAYMENTS = 5

    Result = Struct.new(:payments, :payment_method, :amount_received, :change_given, keyword_init: true)

    def self.call(company, total, params) = new(company, total, params).call

    def initialize(company, total, params)
      @company = company
      @total   = total
      @params  = params
    end

    def call
      list = payments_from_params
      fail!(:too_many_payments) if list.empty? || list.size > MAX_PAYMENTS
      list.each_with_index { |payment, index| check_method!(payment, index) }
      fail!(:multiple_cash) if list.count { |p| p[:method] == "cash" } > 1

      non_cash = list.each_with_index.filter_map { |payment, index| non_cash_attributes(payment, index) unless payment[:method] == "cash" }
      paid = non_cash.sum { |attrs| attrs[:amount] }
      fail!(:exceeds_total) if paid > @total

      cash_index = list.index { |p| p[:method] == "cash" }
      attributes = non_cash
      if cash_index
        # El efectivo conserva su lugar en la lista, para que el ticket muestre los pagos en el orden capturado.
        attributes = non_cash.dup.insert(cash_index, cash_attributes(list[cash_index], @total - paid, cash_index))
      elsif paid < @total
        fail!(:missing, missing: (@total - paid).to_s("F"))
      end

      build_result(attributes)
    end

    private

    # Formato anterior (un método y lo recibido) para la app que ya está instalada (research R2).
    def payments_from_params
      raw = @params[:payments]
      return Array(raw).map { |p| p.to_h.symbolize_keys } if raw.present?

      method = @params[:payment_method].to_s
      return [ { method: method, amount_received: @params[:amount_received], legacy: true } ] if method == "cash"

      [ { method: method, amount: @total, legacy: true } ]
    end

    def check_method!(payment, index)
      return if METHODS.include?(payment[:method].to_s)

      raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("ticket.invalid_payment_method"), details: { index: index })
    end

    def non_cash_attributes(payment, index)
      amount = decimal(payment[:amount])
      fail!(:invalid_amount, index: index) unless amount&.positive?

      if payment[:method].to_s == "transfer"
        reference = payment[:reference].to_s.strip
        return { payment_method: :transfer, amount: amount, legacy: true } if reference.empty? && payment[:legacy]

        fail!(:reference_required, index: index) if reference.empty?
        return { payment_method: :transfer, amount: amount, reference: reference }
      end

      card_attributes(payment, amount, index)
    end

    def card_attributes(payment, amount, index)
      last4 = payment[:card_last4].to_s.strip.presence
      fail!(:invalid_card_last4, index: index) if last4 && last4 !~ /\A\d{4}\z/

      terminal = nil
      if payment[:terminal_id].present?
        terminal = PaymentTerminal.usable_for(@company, payment[:terminal_id])
        fail!(:invalid_terminal, index: index) unless terminal
      end

      { payment_method: :card, amount: amount, terminal: terminal,
        authorization_code: payment[:authorization_code].to_s.strip.presence, card_last4: last4 }
    end

    # El efectivo cubre lo que falta; lo recibido de más es el cambio.
    def cash_attributes(payment, due, index)
      fail!(:invalid_amount, index: index) unless due.positive?

      received = decimal(payment[:amount_received]) || BigDecimal("0")
      if received < due
        missing = (due - received).to_s("F")
        # La app instalada muestra el mensaje de siempre (research R2).
        if payment[:legacy]
          raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("ticket.insufficient_cash"), details: { code: "missing", missing: missing })
        end
        fail!(:missing, index: index, missing: missing)
      end

      { payment_method: :cash, amount: due, amount_received: received }
    end

    def build_result(attributes)
      methods = attributes.map { |attrs| attrs[:payment_method] }.uniq
      cash = attributes.find { |attrs| attrs[:payment_method] == :cash }
      received = attributes.sum { |attrs| attrs[:payment_method] == :cash ? attrs[:amount_received] : attrs[:amount] }
      Result.new(
        payments: attributes,
        payment_method: methods.size == 1 ? methods.first.to_s : "mixed",
        amount_received: received,
        change_given: cash ? cash[:amount_received] - cash[:amount] : BigDecimal("0")
      )
    end

    def decimal(value)
      return nil if value.to_s.strip.empty?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def fail!(code, **details)
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("ticket.charge.#{code}"), details: { code: code.to_s, **details }
      )
    end
  end
end
