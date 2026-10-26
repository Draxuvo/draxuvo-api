# Borra las demos vencidas o terminadas (spec 039, R6). Corre cada 10 minutos (config/recurring.yml) y también se
# encola con una empresa concreta cuando el visitante pulsa «Salir de la demo».
module Demo
  class PurgeJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 20

    def perform(company_id: nil, batch_size: BATCH_SIZE)
      return purge_company(Company.demo.find_by(id: company_id)) if company_id

      DemoSession.purgeable.order(:expires_at).limit(batch_size).each do |session|
        company = session.company
        company ? purge_company(company) : session.update!(purged_at: Time.current, ended_reason: session.ended_reason || "expired")
      end
    end

    private

    def purge_company(company)
      return unless company&.demo?

      Demo::Purge.call(company)
    end
  end
end
