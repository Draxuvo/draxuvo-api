# Quién puede qué en una venta de mostrador (spec 050, FR-061 y FR-030). Las reglas viven aquí y no en la UI.
module Sales
  module Permissions
    BOSS_ROLES = Authorizable::BOSS_ROLES

    # Quién actúa: la persona (User) y su rol en la empresa activa.
    Context = Struct.new(:user, :role, keyword_init: true) do
      def boss? = BOSS_ROLES.include?(role)

      def opener_of?(sale) = sale.opened_by_id == user.id
    end

    module_function

    # Ver, editar, retomar y cobrar: dueño y administrador cualquiera; el resto, las que abrió.
    def access?(sale, context) = context.boss? || context.opener_of?(sale)

    # Descartar solo aplica a una venta abierta.
    def discard?(sale, context) = sale.status_open? && access?(sale, context)

    # Cancelar una venta ya cobrada: solo dueño y administrador.
    def cancel?(_sale, context) = context.boss?

    def actions(sale, context)
      return [] unless access?(sale, context)

      case sale.status
      when "open" then %w[add_item charge discard]
      when "paid" then context.boss? ? %w[ticket cancel] : %w[ticket]
      else %w[ticket]
      end
    end
  end
end
