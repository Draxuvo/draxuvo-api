module Push
  # Alertas operativas por push a dueño y administradores (spec 057, US4, FR-012, FR-012a, FR-013). Corre cada minuto:
  # arma las alertas de cada empresa con `Alerts::Collector` (las mismas de la campana) y avisa una sola vez por
  # alerta. `push_alert_notices` recuerda lo avisado: una alerta pospuesta (la posposición es de la empresa) queda
  # «rearmada» y se avisa una vez más si sigue al terminar; la de un elemento que avanzó se olvida. El stock bajo no
  # sale aquí (lo manda `Push::LowStock` con el aviso inmediato). Si Expo falla, la alerta no se marca y se intenta
  # en la siguiente revisión.
  class AlertsScan
    KIND = "operational_alert".freeze
    BODY_KEYS = {
      "kitchen_wait" => "alert_kitchen_wait",
      "kitchen_preparing" => "alert_kitchen_preparing",
      "work_order_stalled" => "alert_work_order_stalled",
      "table_open" => "alert_table_open"
    }.freeze
    LABEL_MAX = 80

    def self.call(now: Time.current) = new(now).call

    def initialize(now)
      @now = now
    end

    def call
      companies.each do |company|
        scan(company)
      rescue => e
        Rails.logger.error("[Push::AlertsScan] company=#{company.id}: #{e.class}: #{e.message}")
      end
    end

    # Solo empresas con algún jefe que tenga un teléfono activo y el tipo encendido (una consulta), y que puedan recibir.
    def companies
      with_devices = PushDevice.active.select(:user_id)
      turned_off = NotificationPreference.where(push_operational_alerts: false).select(:user_id, :company_id)
      ids = UserCompany.where(role: %i[owner admin], user_id: with_devices)
                       .where.not("(user_companies.user_id, user_companies.company_id) IN (#{turned_off.to_sql})")
                       .distinct.pluck(:company_id)
      Company.real.where(id: ids).includes(:subscription, parent: :subscription).select { |company| Eligibility.company_ok?(company, KIND) }
    end

    def scan(company)
      results = PushDevice::LOCALES.index_with { |locale| I18n.with_locale(locale) { Alerts::Collector.new(company, now: @now).call } }
      labels = results.transform_values do |result|
        (result.results + result.snoozed.map(&:first)).to_h { |alert| [ alert.id, alert.subject[:label] ] }
      end
      active = results.fetch("es").results.select { |alert| BODY_KEYS.key?(alert.kind) }
      snoozed = results.fetch("es").snoozed.map(&:first).select { |alert| BODY_KEYS.key?(alert.kind) }

      notices = company.push_alert_notices.index_by { |notice| [ notice.kind, notice.subject_key ] }
      live = (active + snoozed).map(&:snooze_key)
      company.push_alert_notices.where(id: notices.except(*live).values.map(&:id)).delete_all

      snoozed.each { |alert| rearm(company, notices[alert.snooze_key], alert) }
      active.each do |alert|
        notice = notices[alert.snooze_key]
        next if notice && !notice.rearm

        notify(company, alert, labels)
        notice ? notice.update!(notified_at: @now, rearm: false) : create_notice(company, alert, rearm: false)
      rescue ExpoClient::Transient => e
        Rails.logger.warn("[Push::AlertsScan] company=#{company.id} alert=#{alert.id}: #{e.message}")
      end
    end

    private

    def rearm(company, notice, alert)
      return notice.update!(rearm: true) if notice && !notice.rearm

      create_notice(company, alert, rearm: true) unless notice
    end

    def create_notice(company, alert, rearm:)
      company.push_alert_notices.create!(kind: alert.kind, subject_key: alert.subject_key, notified_at: @now, rearm: rearm)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def notify(company, alert, labels)
      label = ->(locale) { Message.truncate(labels.dig(locale, alert.id) || labels.dig("es", alert.id), LABEL_MAX) }
      message = Message.new(kind: KIND, company: company, path: "/alertas", subject_id: alert.subject[:id],
                            body_key: BODY_KEYS.fetch(alert.kind),
                            body_args: { label: label, duration: ->(locale) { Elapsed.format(alert.minutes, locale: locale) } })
      company.user_companies.where(role: %i[owner admin]).includes(:user).each do |membership|
        Deliver.call(company: company, user: membership.user, message: message, subject_key: alert.id.first(200))
      end
    end
  end
end
