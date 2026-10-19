# Deja las membresías de un usuario igual a la lista recibida (spec 014, data-model.md): crea las nuevas,
# cambia el rol de las existentes y quita las que no vienen. Mismas reglas que /company/members:
# solo roles de empresa (nunca super_admin) y ninguna empresa se queda sin su último owner.
# No abre transacción: la abre quien lo llama junto con el resto del guardado.
module Users
  class SyncMemberships
    def initialize(user, memberships)
      @user = user
      @memberships = memberships.map { |m| { company_id: m[:company_id].to_i, role: (m[:role].presence || "staff").to_s } }
    end

    def call
      validate!
      current = @user.user_companies.to_a.index_by(&:company_id)
      wanted = @memberships.to_h { |m| [ m[:company_id], m[:role] ] }

      current.each_value { |membership| ensure_owner_kept!(membership, wanted[membership.company_id]) }

      current.each { |company_id, membership| membership.destroy! unless wanted.key?(company_id) }
      wanted.each do |company_id, role|
        membership = current[company_id] || @user.user_companies.build(company_id: company_id)
        membership.update!(role: role)
      end
      @user.user_companies.reset
      @user.companies.reset
    end

    private

    def validate!
      @memberships.each do |m|
        raise ApiErrors::BadRequestError.new(details: { role: m[:role] }) unless UserCompany.roles.key?(m[:role])
      end

      ids = @memberships.map { |m| m[:company_id] }
      duplicate = ids.detect { |id| ids.count(id) > 1 }
      unprocessable!("duplicate_company", duplicate, I18n.t("users.duplicate_company")) if duplicate

      missing = (ids - Company.where(id: ids).ids).first
      unprocessable!("company_not_found", missing, I18n.t("users.company_not_found")) if missing
    end

    # Un owner que se quita o baja de rol necesita otro owner en su empresa.
    def ensure_owner_kept!(membership, new_role)
      return unless membership.owner? && new_role != "owner"
      return if UserCompany.owner.where(company_id: membership.company_id).where.not(id: membership.id).exists?

      unprocessable!("last_owner", membership.company_id, I18n.t("company_members.last_owner"))
    end

    def unprocessable!(code, company_id, message)
      raise ApiErrors::UnprocessableEntityError.new(message: message, details: { code: code, company_id: company_id })
    end
  end
end
