# Cambios de estado de una orden (spec 007). Cada acción valida el estado de origen y el rol, y
# guarda el cambio, el evento de historia y, en el cobro, el ticket, todo en una sola transacción.
module WorkOrders
  class Transition
    BOSS_ROLES  = Authorizable::BOSS_ROLES
    ADMIN_ROLES = Authorizable::ADMIN_ROLES
    PAYMENT_METHODS = Ticket.payment_methods.keys.freeze

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

    def charge
      method = @params[:payment_method].to_s
      unless PAYMENT_METHODS.include?(method)
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("ticket.invalid_payment_method"))
      end

      @order.recalculate_total!
      total = @order.total
      if @order.work_order_items.none? { |item| item.unit_price.to_f.positive? } || !total.positive?
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("work_order.no_items"), details: { reason: "no_items" })
      end

      received = method == "cash" ? decimal(@params[:amount_received]) : total
      if received < total
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("ticket.insufficient_cash"),
          details: { missing: (total - received).to_s("F") }
        )
      end

      ticket = @order.ticket || @order.build_ticket(company: @order.company)
      ticket.assign_attributes(
        status: :paid, total: total, payment_method: method, amount_received: received,
        change_given: received - total, charged_by: @context.user, paid_at: Time.current,
        voided_at: nil, voided_by: nil, void_reason: nil
      )
      ticket.save!
      @order.update!(status: :paid)
      event(:charged, { ticket_id: ticket.id, folio: ticket.folio, payment_method: method, total: total.to_s("F"),
                        amount_received: received.to_s("F"), change_given: (received - total).to_s("F") })
    end

    def void_charge
      reason = require_reason!
      ticket = @order.ticket
      ticket.update!(status: :voided, voided_at: Time.current, voided_by: @context.user, void_reason: reason)
      @order.update!(status: :done)
      event(:voided, { ticket_id: ticket.id, reason: reason })
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
