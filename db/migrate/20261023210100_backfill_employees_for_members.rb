# Spec 036: toda persona con acceso a una empresa tiene ficha de empleado. Crea la que falte, activa y sin
# correo (employees.email es único en toda la base; el correo se ve por el usuario ligado). Idempotente.
class BackfillEmployeesForMembers < ActiveRecord::Migration[8.0]
  class Membership < ActiveRecord::Base
    self.table_name = "user_companies"
  end

  class Person < ActiveRecord::Base
    self.table_name = "users"
  end

  class Ficha < ActiveRecord::Base
    self.table_name = "employees"
  end

  def up
    Membership.find_each do |m|
      next if Ficha.exists?(company_id: m.company_id, user_id: m.user_id)

      user = Person.find_by(id: m.user_id)
      next unless user

      name = [ user.first_name, user.last_name ].compact_blank.join(" ").presence || user.email
      Ficha.create!(company_id: m.company_id, user_id: user.id, name: name, status: 0)
    end
  end

  def down; end
end
