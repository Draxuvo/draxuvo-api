# Borra las demos vencidas o terminadas (spec 039, R6). Corre cada 10 minutos (config/recurring.yml) y también se
# encola con una empresa concreta cuando el visitante pulsa «Salir de la demo».
#
# Cada demo se purga aparte (spec 062): si una falla, queda intacta (la purga es todo o nada), el error va al log, la
# apertura se marca con `purge_failed_at` y el job sigue con las demás. Las que fallaron pasan al final del lote
# (`DemoSession.purge_order`), así que se reintentan sin impedir que se borren las sanas.
module Demo
  class PurgeJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 20

    def perform(company_id: nil, batch_size: BATCH_SIZE)
      return purge_company(Company.demo.find_by(id: company_id)) if company_id

      DemoSession.purgeable.purge_order.limit(batch_size).each do |session|
        company = session.company
        company ? purge_company(company, session) : session.update!(purged_at: Time.current, ended_reason: session.ended_reason || "expired")
      end
    end

    private

    def purge_company(company, session = company&.demo_session)
      return unless company&.demo?

      Demo::Purge.call(company)
    rescue StandardError => e
      Rails.logger.error("[Demo::PurgeJob] company=#{company.id} session=#{session&.id}: #{e.class}: #{e.message}")
      session&.update_column(:purge_failed_at, Time.current)
    end
  end
end
