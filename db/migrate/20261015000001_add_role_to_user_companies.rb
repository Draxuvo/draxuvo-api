# El rol pasa a ser por empresa (spec 004, R16). Cada membresía recibe el rol global actual del
# usuario para que nadie pierda acceso; super_admin sigue siendo global y solo vive en users.role
# (sus membresías, si las tiene, quedan como owner).
class AddRoleToUserCompanies < ActiveRecord::Migration[8.0]
  def up
    add_column :user_companies, :role, :integer, null: false, default: 0

    execute <<~SQL.squish
      UPDATE user_companies
      SET role = LEAST(COALESCE(users.role, 0), 3)
      FROM users
      WHERE users.id = user_companies.user_id
    SQL
  end

  def down
    remove_column :user_companies, :role
  end
end
