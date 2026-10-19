# Quién puede qué en el restaurante (research R6). Las reglas viven aquí y no en la app.
module Restaurant
  module Permissions
    BOSS_ROLES = Authorizable::BOSS_ROLES

    # Quién actúa: la persona (User) y su rol en la empresa activa.
    Context = Struct.new(:user, :role, keyword_init: true) do
      def boss? = BOSS_ROLES.include?(role)

      def waiter_of?(check) = check.waiter_id == user.id
    end

    module_function

    def pay?(check, context) = context.boss? || context.waiter_of?(check)

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
