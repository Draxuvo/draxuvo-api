# Borra una demo por completo (spec 039, R6): sucursales, empresa con todo lo que cuelga de ella (apoyado en los
# `dependent` de Company), los usuarios efímeros que solo pertenecían a la demo y los archivos adjuntos. La apertura
# (DemoSession) se conserva con `purged_at`: es lo que necesita el seguimiento comercial.
module Demo
  class Purge
    def self.call(company) = new(company).call

    def initialize(company)
      @company = company
    end

    def call
      raise ArgumentError, "no es una empresa de demostración" unless @company.demo?

      session = @company.demo_session
      companies = [ *@company.branches.to_a, @company ]
      user_ids = companies.flat_map { |company| company.users.pluck(:id) }.uniq

      ActiveRecord::Base.transaction do
        companies.each do |company|
          clear_restaurant(company)
          company.destroy!
        end
        orphan_users(user_ids).find_each(&:destroy!)
        mark_purged(session)
      end
    end

    private

    # Las cuentas se quitan antes que las mesas: DiningTable no se deja borrar con cuentas (restrict_with_error) y
    # Company declara `dining_tables` antes que `checks`. Una cuenta cerrada es de solo lectura, así que se borra por
    # SQL y en el orden de sus llaves, sin pasar por sus callbacks.
    def clear_restaurant(company)
      company.tickets.destroy_all
      check_ids = company.checks.pluck(:id)
      return if check_ids.empty?

      [ CheckPayment, CheckItem, KitchenOrder ].each { |model| model.where(check_id: check_ids).delete_all }
      Check.where(id: check_ids).delete_all
    end

    # Usuarios de la demo que ya no pertenecen a ninguna empresa (y no son super admin).
    def orphan_users(ids)
      User.where(id: ids).where.not(role: User.roles[:super_admin])
          .where.not(id: UserCompany.select(:user_id))
    end

    def mark_purged(session)
      return unless session

      session.update!(purged_at: Time.current, ended_reason: session.ended_reason || "expired")
    end
  end
end
