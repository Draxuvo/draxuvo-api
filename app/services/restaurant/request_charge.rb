# «Pedir cobro» (spec 058, FR-023): con «Cobro solo por jefes», el mesero (o un jefe) avisa que el cliente pidió la cuenta.
# La cuenta sigue abierta a pedidos; agregar un artículo quita la marca. Bajo bloqueo de la cuenta.
module Restaurant
  class RequestCharge
    def self.call(check, context) = new(check, context).call

    def initialize(check, context)
      @check = check
      @context = context
    end

    def call
      Check.transaction do
        @check.lock!
        fail!(:check_not_open) unless @check.status_open?
        fail!(:charge_policy_off) unless @check.company.boss_only_charge
        raise ApiErrors::ForbiddenError.new(message: I18n.t("auth.not_authorized")) unless @context.boss? || @context.waiter_of?(@check)
        fail!(:nothing_to_submit) unless Permissions.chargeable?(@check)

        @check.update!(charge_requested_at: Time.current, charge_requested_by: @context.user) if @check.charge_requested_at.nil?
        @check
      end
    end

    private

    def fail!(code)
      raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("restaurant.errors.#{code}"), details: { code: code.to_s })
    end
  end
end
