module Alerts
  # Quién recibe los avisos de stock bajo de una empresa (spec 045): dueños y administradores activos, con el canal
  # encendido. El correo está encendido por omisión; el WhatsApp solo si la persona lo activó y tiene teléfono.
  # Se calcula al enviar, así que quien deja de ser jefe o se da de baja deja de recibir.
  class Recipients
    Recipient = Struct.new(:user, :email, :whatsapp, keyword_init: true)

    def self.call(company) = new(company).call

    def initialize(company)
      @company = company
    end

    def call
      preferences = @company.notification_preferences.index_by(&:user_id)
      inactive = @company.employees.inactive.where.not(user_id: nil).pluck(:user_id)

      memberships.filter_map do |membership|
        user = membership.user
        next if !user.active? || inactive.include?(user.id)

        preference = preferences[user.id]
        email = (preference ? preference.stock_email : true) && user.email.present?
        whatsapp = preference&.stock_whatsapp && user.phone.present?
        Recipient.new(user: user, email: email, whatsapp: whatsapp) if email || whatsapp
      end
    end

    private

    def memberships
      @company.user_companies.where(role: %i[owner admin]).includes(:user)
    end
  end
end
