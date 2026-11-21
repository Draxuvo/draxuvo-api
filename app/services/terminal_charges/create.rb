module TerminalCharges
  # Crea una solicitud de cobro y la manda a la terminal (spec 069, FR-012, FR-016, FR-017, research R6 y R9).
  #
  # 1. Valida: módulo, demo, terminal integrada al corriente, un solo pago integrado y el cobro de siempre en prueba.
  # 2. Crea la fila `pending` (los índices parciales dan 409 si la terminal o el cobro ya tienen una abierta).
  # 3. Ya confirmada la transacción, manda la orden al proveedor. Si falla, la solicitud queda `declined` y se responde.
  class Create
    def self.call(company:, user:, params:) = new(company, user, params).call

    def initialize(company, user, params)
      @company = company
      @user = user
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.with_indifferent_access : params.to_h.with_indifferent_access
    end

    def call
      Demo::Guard.restrict!(:terminal_charge)
      terminal = @company.payment_terminals.find(@params[:terminal_id])
      Errors.invalid!(:terminal_not_chargeable) unless terminal.chargeable?
      amount = decimal(@params[:amount])
      Errors.invalid!(:invalid_amount) unless amount&.positive?

      charge_params = (@params[:params] || {}).to_h.with_indifferent_access
      ensure_single_integrated!(charge_params)
      owner = Owner.find(@company, @user, @params)
      ensure_not_busy!(terminal, owner)
      owner.dry_run!(charge_params, amount: amount, terminal: terminal)

      charge = create_row!(terminal, owner, amount, charge_params)
      send_to_provider(charge)
    end

    private

    def create_row!(terminal, owner, amount, charge_params)
      charge = TerminalCharge.create!(
        company: @company, payment_terminal: terminal, terminal_connection: terminal.terminal_connection, created_by: @user,
        amount: amount, params: charge_params.except(:result), **owner.owner_attributes
      )
      TerminalEvent.log!(:charge_created, charge: charge, user: @user, amount: amount.to_s("F"), owner: owner.type)
      charge
    rescue ActiveRecord::RecordNotUnique
      ensure_not_busy!(terminal, owner)
      raise
    end

    def send_to_provider(charge)
      result = TerminalProviders.for(charge.terminal_connection.provider).create_charge(charge)
      charge.update!(provider_order_id: result.id, provider_payment_id: result.payment_id, last_synced_at: Time.current,
                     status_detail: result.detail || "created")
      charge
    rescue TerminalProviders::Error => e
      fail_charge!(charge, e.failure)
    end

    # El proveedor no tomó el cobro: no queda nada pendiente (FR-015) y se explica.
    def fail_charge!(charge, failure)
      detail = case failure.family
      when :transient then "provider_unavailable"
      when :device then "device_offline"
      else failure.reason == "amount_out_of_range" ? "amount_out_of_range" : (failure.reason.presence || "failed")
      end
      charge.update!(status: "declined", status_detail: detail.first(60), resolved_at: Time.current)
      TerminalEvent.log!(:charge_declined, charge: charge, reason: detail)
      TerminalConnections::Health.failed!(charge.terminal_connection, failure) if failure.connection?

      case detail
      when "provider_unavailable" then Errors.bad_gateway!(:provider_unavailable)
      when "amount_out_of_range" then Errors.invalid!(:amount_out_of_range, terminal_charge_id: charge.id)
      when "device_offline" then Errors.invalid!(:device_offline, terminal_charge_id: charge.id)
      else
        failure.connection? ? Errors.invalid!(:terminal_not_chargeable, terminal_charge_id: charge.id) : Errors.invalid!(:declined, terminal_charge_id: charge.id)
      end
    end

    # FR-017: un solo pago por cobro a una terminal integrada; los demás van en `params` como hoy.
    def ensure_single_integrated!(charge_params)
      ids = Array(charge_params[:payments]).filter_map { |p| p.to_h.with_indifferent_access[:terminal_id].presence }
      return if ids.empty?

      Errors.invalid!(:one_integrated_payment) if @company.payment_terminals.where(id: ids).where.not(device_id: nil).exists?
    end

    def ensure_not_busy!(terminal, owner)
      busy = terminal.terminal_charges.open.first
      Errors.conflict!(:terminal_busy, by: busy.created_by&.full_name) if busy
      pending = TerminalCharge.open_for(owner.record)
      Errors.conflict!(:terminal_charge_pending, terminal_charge_id: pending.id) if pending
    end

    def decimal(value)
      return nil if value.to_s.strip.empty?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
