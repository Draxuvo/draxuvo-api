# Reglas de rol al dar, cambiar o quitar el acceso de una persona a la empresa activa (specs 004, 029 y 036).
# Las usan /company/members y el acceso desde la ficha del empleado:
# - nadie asigna un rol mayor al suyo ni super_admin (403 role_not_allowed);
# - solo un owner asigna o quita owner, y nadie toca a alguien de rango mayor (403);
# - no se quita ni se baja al último owner (422 last_owner), salvo el super admin.
module MembershipRules
  extend ActiveSupport::Concern

  private

  # Rol de empresa válido y no mayor al de quien lo asigna. super_admin nunca es asignable aquí.
  def assignable_role!(role)
    role = role.to_s
    return role if UserCompany.roles.key?(role) && UserCompany.rank(role) <= UserCompany.rank(current_role)

    forbid!(details: { code: "role_not_allowed", role: role })
  end

  # Nadie modifica a alguien de rango mayor; owner solo lo toca otro owner (o el super admin).
  def guard_target!(membership = @membership)
    return if UserCompany.rank(membership.role) <= UserCompany.rank(current_role)

    forbid!(details: { code: "role_not_allowed", role: membership.role })
  end

  def ensure_another_owner!(membership = @membership)
    return if current_role == "super_admin"
    return if current_company.user_companies.owner.where.not(id: membership.id).exists?

    raise ApiErrors::UnprocessableEntityError.new(
      message: I18n.t("company_members.last_owner"),
      details: { code: "last_owner" }
    )
  end

  def send_set_password_email(user)
    Email::SetPasswordService.new(user, company_name: current_company.name).call[:success]
  rescue => e
    Rails.logger.error "[#{self.class.name}] SetPasswordService error class=#{e.class} message=#{e.message}"
    false
  end
end
