# Quién puede qué en el restaurante (research R6). Las reglas viven aquí y no en la app.
module Restaurant
  module Permissions
    BOSS_ROLES = Authorizable::BOSS_ROLES

    # Quién actúa: la persona (User), su rol y la empresa activa (para «Cobro solo por jefes», spec 058).
    Context = Struct.new(:user, :role, :company, keyword_init: true) do
      def boss? = BOSS_ROLES.include?(role)

      def waiter_of?(check) = check.waiter_id == user.id

      def restricted? = company.present? && ChargePolicy.restricted?(company, role)
    end

    module_function

    def pay?(check, context) = (context.boss? || context.waiter_of?(check)) && !context.restricted?

    # Spec 058: con la regla activa, el mesero (o un jefe) avisa que el cliente pidió la cuenta. Hace falta saldo y algo
    # ya mandado; una cuenta que ya lo pidió no lo vuelve a pedir hasta que se le agreguen artículos.
    def request_charge?(check, context)
      context.company.present? && context.company.boss_only_charge && (context.boss? || context.waiter_of?(check)) &&
        check.status_open? && check.charge_requested_at.nil? && chargeable?(check)
    end

    def chargeable?(check)
      check.balance.positive? && check.check_items.where.not(status: %i[draft cancelled]).exists?
    end

    # Por qué no ve Cobrar quien pregunta (para el aviso de la pantalla), o nil.
    def charge_blocked_reason(check, context)
      check.status_open? && context.restricted? ? ChargePolicy::REASON : nil
    end

    def cancel_item?(item, context)
      return false if item.status_delivered? || item.status_cancelled? || item.status_draft?
      return context.boss? unless item.status_new?

      context.boss? || context.waiter_of?(item.check)
    end

    def deliver_item?(item, _context) = item.status_ready?

    def check_actions(check, context)
      return [] unless check.status_open?

      actions = %w[add_item]
      actions << "send" if check.check_items.status_draft.exists?
      actions << "pay" if pay?(check, context)
      actions << "request_charge" if request_charge?(check, context)
      actions << "reassign" if context.boss?
      actions << "cancel" if check.check_items.where.not(status: :draft).none? && (context.boss? || context.waiter_of?(check))
      actions << "close" if check.total.zero? && check.check_items.counted.none? && context.boss? && check.check_items.status_draft.none?
      actions
    end

    def item_actions(item, context)
      actions = []
      actions << "deliver" if deliver_item?(item, context)
      actions << "cancel" if cancel_item?(item, context)
      actions
    end
  end
end
