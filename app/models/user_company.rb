# Membresía de un usuario en una empresa, con su rol en esa empresa (spec 004, R16).
# super_admin no es un rol de empresa: es global y vive en users.role.
class UserCompany < ApplicationRecord
  belongs_to :user
  belongs_to :company

  enum :role, { staff: 0, manager: 1, admin: 2, owner: 3 }, default: :staff

  # Rango para comparar roles; super_admin queda por encima de todos.
  RANKS = roles.merge("super_admin" => 4).freeze

  validates :user_id, uniqueness: { scope: :company_id }

  def self.rank(role) = RANKS.fetch(role.to_s, -1)
end
