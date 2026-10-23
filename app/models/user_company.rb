# Membresía de un usuario en una empresa, con su rol en esa empresa (spec 004, R16).
# super_admin no es un rol de empresa: es global y vive en users.role.
class UserCompany < ApplicationRecord
  belongs_to :user
  belongs_to :company

  enum :role, { staff: 0, manager: 1, admin: 2, owner: 3 }, default: :staff

  # Rango para comparar roles; super_admin queda por encima de todos.
  RANKS = roles.merge("super_admin" => 4).freeze

  validates :user_id, uniqueness: { scope: :company_id }

  # Spec 036: toda persona con acceso tiene ficha de empleado en la empresa (se crea al darle acceso), y quitarle el
  # acceso suelta su ficha —que se conserva con su asistencia— sin dejarla ligada a un usuario que ya no entra.
  after_create :ensure_employee
  after_destroy :release_employee

  def self.rank(role) = RANKS.fetch(role.to_s, -1)

  private

  def ensure_employee
    return if company.employees.exists?(user_id: user_id)

    company.employees.create!(user: user, name: user.full_name.presence || user.email, status: :active)
  end

  def release_employee
    company.employees.where(user_id: user_id).update_all(user_id: nil, updated_at: Time.current)
  end
end
