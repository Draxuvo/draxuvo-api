module Push
  # Quién recibe un aviso push (spec 057, FR-015). La empresa: real (no demo), con acceso por su suscripción y con el
  # módulo del tipo activo, y el envío no apagado con `PUSH_ENABLED=false`. La persona: activa, miembro de la empresa con
  # un rol que el tipo admite, sin ficha de empleado dada de baja ahí, con el tipo encendido y con algún dispositivo activo.
  module Eligibility
    module_function

    def enabled? = ENV.fetch("PUSH_ENABLED", "true") != "false"

    def company_ok?(company, kind)
      enabled? && !company.demo? && company.billing_subscription&.active_access? == true && Kinds.module_active?(kind, company)
    end

    # :ok, :ineligible (no se registra), :skipped_preference o :no_devices.
    def recipient_status(user, company, kind)
      return :ineligible unless user&.active?

      membership = company.user_companies.find_by(user_id: user.id)
      return :ineligible unless membership && Kinds.allowed_role?(kind, membership.role)
      return :ineligible if company.employees.inactive.exists?(user_id: user.id)
      return :skipped_preference unless NotificationPreference.for(user, company).push_enabled?(kind)
      return :no_devices unless user.push_devices.active.exists?

      :ok
    end
  end
end
