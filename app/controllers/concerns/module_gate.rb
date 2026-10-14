# Bloquea acciones cuyo módulo no está en el plan de la empresa (403 module_not_in_plan).
# Uso: requires_module :inventory, only: %i[create update]
module ModuleGate
  extend ActiveSupport::Concern

  class_methods do
    def requires_module(key, **options)
      before_action(-> { check_module!(key) }, **options)
    end
  end

  private

  def check_module!(key)
    return if current_user&.super_admin?
    return if current_company.module_active?(key)

    raise_module_not_in_plan!(key)
  end

  def raise_module_not_in_plan!(key)
    raise ApiErrors::ForbiddenError.new(
      message: I18n.t("errors.module_not_in_plan", module: I18n.t("modules.#{key}")),
      details: { code: "module_not_in_plan", module: key.to_s }
    )
  end
end
