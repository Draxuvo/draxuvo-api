# Cambios de estado de una orden (spec 007). Cada acción valida el estado de origen y el rol, y
# guarda el cambio, el evento de historia y, en el cobro, el ticket, todo en una sola transacción.
module WorkOrders
  class Transition
    BOSS_ROLES  = Authorizable::BOSS_ROLES
    ADMIN_ROLES = Authorizable::ADMIN_ROLES

    # Quién actúa: la persona (User), su rol en la empresa y su empleado en esa empresa (si tiene).
    Context = Struct.new(:user, :role, :employee, keyword_init: true) do
      def boss?  = BOSS_ROLES.include?(role)
      def admin? = ADMIN_ROLES.include?(role)

      def assigned_to?(order)
        employee.present? && order.employee_id == employee.id
      end
    end

    # acción => [estados de origen, quién puede]
    RULES = {
      start:       { from: %w[open],                          who: :worker },
      finish:      { from: %w[open in_progress],              who: :worker },
      reopen:      { from: %w[done],                          who: :worker },
      charge:      { from: %w[done],                          who: :worker },
      cancel:      { from: %w[open in_progress done],         who: :boss },
      void_charge: { from: %w[paid],                          who: :admin }
    }.freeze

    def self.call(order, action, context, params = {})
      new(order, action, context, params).call
    end

    # Acciones que `context` puede ejecutar ahora sobre `order` (para allowed_actions).
    def self.allowed(order, context)
      RULES.keys.select { |action| permitted?(order, action, context) && RULES[action][:from].include?(order.status) }
    end

    def self.permitted?(order, action, context)
      case RULES.fetch(action)[:who]
      when :worker then context.boss? || context.assigned_to?(order)
      when :boss   then context.boss?
      when :admin  then context.admin?
      end
    end

    def initialize(order, action, context, params)
      @order   = order
      @action  = action.to_sym
      @context = context
      @params  = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.with_indifferent_access : params.to_h.with_indifferent_access
    end

    def call
      rule = RULES[@action] or raise ApiErrors::BadRequestError.new(details: @action.to_s)
      raise ApiErrors::ForbiddenError.new(message: I18n.t("auth.not_authorized")) unless self.class.permitted?(@order, @action, @context)

      WorkOrder.transaction do
        @order.lock!
        unless rule[:from].include?(@order.status)
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("work_order.invalid_transition"),
            details: { from: @order.status, action: @action.to_s }
          )
        end
        send(@action)
      end
      @order.reload
    end

    private

    def start
      @order.update!(status: :in_progress, started_at: Time.current)
      event(:started)
    end

    def finish
      pending = @order.work_order_steps.where(done_at: nil).count
      @order.update!(status: :done, completed_at: Time.current)
      event(:finished, pending > 0 ? { pending_steps: pending } : {})
    end

    def reopen
      @order.update!(status: :in_progress, completed_at: nil)
      event(:reopened)
    end

    def cancel
      reason = require_reason!
      @order.update!(status: :cancelled, cancel_reason: reason)
      event(:cancelled, { reason: reason })
    end

    # Uno o varios pagos (spec 015); `ChargePayments` valida y reparte, aquí se guarda todo junto.
    def charge
      @order.recalculate_total!
      total = @order.total
      if @order.work_order_items.none? { |item| item.unit_price.to_f.positive? } || !total.positive?
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("work_order.no_items"), details: { reason: "no_items" })
      end

      split = ChargePayments.call(@order.company, total, @params)
      ticket = @order.ticket || @order.build_ticket(company: @order.company)
      ticket.assign_attributes(
        status: :paid, total: total, payment_method: split.payment_method, amount_received: split.amount_received,
        change_given: split.change_given, charged_by: @context.user, paid_at: Time.current,
        voided_at: nil, voided_by: nil, void_reason: nil
      )
      ticket.save!
      split.payments.each do |attrs|
        ticket.ticket_payments.create!(attrs.merge(company: @order.company, created_by: @context.user))
      end
      @order.update!(status: :paid)
      event(:charged, { ticket_id: ticket.id, folio: ticket.folio, payment_method: split.payment_method, total: total.to_s("F"),
                        amount_received: split.amount_received.to_s("F"), change_given: split.change_given.to_s("F"),
                        payments: payments_summary(split.payments) })
    end

    # Los pagos quedan anulados y en la historia; al volver a cobrar se usa el mismo folio (research R6).
    def void_charge
      reason = require_reason!
      ticket = @order.ticket
      now = Time.current
      voided = ticket.ticket_payments.active.to_a
      ticket.ticket_payments.active.update_all(voided_at: now, updated_at: now)
      ticket.update!(status: :voided, voided_at: now, voided_by: @context.user, void_reason: reason)
      @order.update!(status: :done)
      event(:voided, { ticket_id: ticket.id, reason: reason, payments: payments_summary(voided) })
    end

    def payments_summary(payments)
      payments.map do |payment|
        method = payment.respond_to?(:payment_method) ? payment.payment_method : payment[:payment_method]
        amount = payment.respond_to?(:amount) ? payment.amount : payment[:amount]
        { method: method.to_s, amount: amount.to_s("F") }
      end
    end

    def require_reason!
      reason = @params[:reason].to_s.strip
      raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("work_order.reason_required")) if reason.empty?

      reason
    end

    def decimal(value)
      BigDecimal(value.to_s)
    rescue ArgumentError
      BigDecimal("0")
    end

    def event(kind, data = {})
      @order.work_order_events.create!(kind: kind, actor: @context.user, data: data)
    end
  end
end
