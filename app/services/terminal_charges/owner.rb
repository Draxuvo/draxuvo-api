module TerminalCharges
  # Lo que se cobra en la terminal: una orden de trabajo, una venta de mostrador o una cuenta de mesa (spec 069, R6).
  # Sabe validar el cobro de siempre sin guardarlo (`dry_run!`) y aplicarlo de verdad (`apply!`) con un pago de tarjeta
  # armado por el servidor. Los permisos y la regla de «cobro solo por jefes» (spec 058) son los del cobro de siempre.
  class Owner
    TYPES = %w[work_order sale check].freeze

    attr_reader :record, :type

    # Resuelve el dueño dentro de la empresa. `params` trae exactamente uno de work_order_id, sale_id o check_id.
    def self.find(company, user, params)
      given = TYPES.select { |type| params["#{type}_id"].present? }
      unless given.one?
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("terminal_charge.errors.invalid_owner"),
                                                      details: { code: "invalid_owner" })
      end

      type = given.first
      scope = { "work_order" => company.work_orders, "sale" => company.sales, "check" => company.checks }.fetch(type)
      new(scope.find(params["#{type}_id"]), user)
    end

    def self.for_charge(charge) = new(charge.owner, charge.created_by)

    def initialize(record, user)
      @record = record
      @user = user
      @company = record.company
      @type = case record
      when WorkOrder then "work_order"
      when Sale then "sale"
      else "check"
      end
    end

    def owner_attributes = { "#{@type}_id": @record.id }

    def label
      case @type
      when "work_order" then @record.title.presence || "##{@record.id}"
      when "sale" then "##{@record.id}"
      else @record.dining_table&.name || @record.takeout_name.presence || "##{@record.id}"
      end
    end

    # Corre el cobro de siempre con la tarjeta en `terminal` y lo revierte: sus errores (reparto, permisos, spec 058,
    # venta cambiada, saldo) salen antes de cobrarle al cliente.
    def dry_run!(params, amount:, terminal:)
      ActiveRecord::Base.transaction(requires_new: true) do
        run(params, { amount: amount, terminal: terminal, source: :manual })
        raise ActiveRecord::Rollback
      end
    ensure
      # El cobro de prueba cambió el registro en memoria (estado, totales): se vuelve a leer lo que de verdad hay.
      @record.reload
    end

    # Aplica el cobro con el pago confirmado. Devuelve [pago creado, resultado para la pantalla].
    def apply!(params, terminal_payment)
      result = run(params, terminal_payment.merge(source: :terminal))
      payment = result[:payment] || find_payment(terminal_payment[:terminal_charge])
      [ payment, result.except(:payment) ]
    end

    private

    def role = @user.role_in(@company)

    def run(params, terminal_payment)
      case @type
      when "work_order" then run_work_order(params, terminal_payment)
      when "sale" then run_sale(params, terminal_payment)
      else run_check(params, terminal_payment)
      end
    end

    def run_work_order(params, terminal_payment)
      employee = @company.employees.find_by(user_id: @user.id)
      context = WorkOrders::Transition::Context.new(user: @user, role: role, employee: employee)
      # Como el controlador: el personal solo ve sus órdenes.
      raise ActiveRecord::RecordNotFound if role == "staff" && !(employee && @record.employee_id == employee.id)

      transition = WorkOrders::Transition.new(@record, :charge, context, params, terminal_payment)
      transition.call
      { work_order_id: @record.id, stock_shortages: transition.shortages }
    end

    def run_sale(params, terminal_payment)
      context = Sales::Permissions::Context.new(user: @user, role: role, company: @company)
      raise ActiveRecord::RecordNotFound unless Sales::Permissions.access?(@record, context)

      ChargePolicy.forbid! if context.restricted?
      result = Sales::Charge.call(@record, @user, params, terminal_payment)
      { sale_id: @record.id, shortages: result.shortages }
    end

    def run_check(params, terminal_payment)
      context = Restaurant::Permissions::Context.new(user: @user, role: role, company: @company)
      result = Restaurant::AddPayment.call(@record, context, params, terminal_payment)
      { check_id: @record.id, payment: result.payment, ticket_id: result.close&.ticket&.id }
    end

    def find_payment(charge)
      return nil unless charge

      TicketPayment.find_by(terminal_charge_id: charge.id) || CheckPayment.find_by(terminal_charge_id: charge.id)
    end
  end
end
