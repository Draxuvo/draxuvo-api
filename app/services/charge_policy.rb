# «Cobro solo por jefes» (spec 058). Con la opción de la empresa encendida, solo dueño, administrador y super admin cobran
# ventas de mostrador, órdenes de trabajo y cuentas de mesa. La regla se decide con el rol en la empresa activa (FR-014).
module ChargePolicy
  REASON = "boss_only".freeze

  module_function

  def restricted?(company, role)
    company.boss_only_charge && !Authorizable::BOSS_ROLES.include?(role.to_s)
  end

  # 403 con un código propio, distinto del rechazo genérico de permisos (FR-007).
  def forbid!
    raise ApiErrors::ForbiddenError.new(message: I18n.t("charge_policy.errors.charge_boss_only"), details: { code: "charge_boss_only" })
  end
end
