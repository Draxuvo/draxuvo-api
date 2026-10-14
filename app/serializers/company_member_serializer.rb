# Contrato: specs/004-refactor-web-panel/contracts/api.md ("GET /company/members").
# Un miembro es el usuario con su rol en la empresa activa (la membresía).
class CompanyMemberSerializer
  def initialize(membership)
    @membership = membership
  end

  def as_json(*)
    user = @membership.user
    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      phone: user.phone,
      role: @membership.role,
      active: user.active
    }
  end
end
