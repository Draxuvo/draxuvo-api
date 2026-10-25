# El rol de gerente (1) sale por ahora: quien lo tenía pasa a staff. Los valores de admin (2) y dueño (3) no cambian.
class RemoveManagerRole < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE user_companies SET role = 0 WHERE role = 1"
    execute "UPDATE users SET role = 0 WHERE role = 1"
  end

  def down
    # Los gerentes que pasaron a staff no se pueden distinguir de los demás.
  end
end
