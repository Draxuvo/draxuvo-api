module Alerts
  # Quién recibe por correo los avisos de stock bajo de una empresa (spec 045): dueños y administradores activos con el
  # correo encendido (por omisión sí) y con correo registrado. Desde la spec 048 WhatsApp ya no es un canal de avisos:
  # una preferencia vieja de WhatsApp no cuenta (ni siquiera el teléfono). Quien tenga el correo apagado no recibe nada
  # externo, pero la alerta sigue en el panel y en la app (`Alerts::Collector`).
  # Se calcula al enviar, así que quien deja de ser jefe o se da de baja deja de recibir.
  class Recipients
    Recipient = Struct.new(:user, :email, keyword_init: true)

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
        Recipient.new(user: user, email: true) if email
      end
    end

    private

    def memberships
      @company.user_companies.where(role: %i[owner admin]).includes(:user)
    end
  end
end
