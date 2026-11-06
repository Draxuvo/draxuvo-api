# Quién puede qué en una venta de mostrador (spec 050, FR-061 y FR-030; spec 058). Las reglas viven aquí y no en la UI.
module Sales
  module Permissions
    BOSS_ROLES = Authorizable::BOSS_ROLES

    # Quién actúa: la persona (User), su rol y la empresa activa (para «Cobro solo por jefes», spec 058).
    Context = Struct.new(:user, :role, :company, keyword_init: true) do
      def boss? = BOSS_ROLES.include?(role)

      def opener_of?(sale) = sale.opened_by_id == user.id

      # Con la opción de la empresa encendida, el personal no cobra (spec 058).
      def restricted? = company.present? && ChargePolicy.restricted?(company, role)
    end

    module_function

    # Ver y retomar: dueño y administrador cualquiera; el resto, las que abrió.
    def access?(sale, context) = context.boss? || context.opener_of?(sale)

    # Cobrar: como ver, salvo que la regla de la empresa reserve el cobro a los jefes (spec 058).
    def charge?(sale, context) = sale.status_open? && access?(sale, context) && !context.restricted?

    # Agregar, cambiar o quitar renglones y descartar: una venta lista para cobro solo la tocan los jefes (spec 058).
    def edit?(sale, context)
      access?(sale, context) && (context.boss? || !sale.submitted? || !context.restricted?)
    end

    # Descartar solo aplica a una venta abierta.
    def discard?(sale, context) = sale.status_open? && edit?(sale, context)

    # Pasar a cobro: el cajero que la abrió, con la regla activa. Un jefe nunca está restringido: cobra directo.
    def submit?(sale, context)
      context.restricted? && context.opener_of?(sale) && sale.status_open? && !sale.submitted?
    end

    # Regresar al cajero una venta lista para cobro: solo jefes.
    def return?(sale, context) = context.boss? && sale.submitted?

    # Cancelar una venta ya cobrada: solo dueño y administrador.
    def cancel?(_sale, context) = context.boss?

    # Por qué no ve Cobrar quien pregunta (para el aviso de la pantalla), o nil.
    def charge_blocked_reason(sale, context)
      sale.status_open? && access?(sale, context) && context.restricted? ? ChargePolicy::REASON : nil
    end

    def actions(sale, context)
      return [] unless access?(sale, context)

      case sale.status
      when "open" then open_actions(sale, context)
      when "paid" then context.boss? ? %w[ticket cancel] : %w[ticket]
      else %w[ticket]
      end
    end

    def open_actions(sale, context)
      return [] unless edit?(sale, context)

      actions = %w[add_item]
      actions << "charge" if charge?(sale, context)
      actions << "discard"
      actions << "return" if return?(sale, context)
      actions << "submit" if submit?(sale, context) && sale.sale_items.any?
      actions
    end
  end
end
