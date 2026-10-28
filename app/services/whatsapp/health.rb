module Whatsapp
  # Salud del canal de WhatsApp (spec 047): el único que cambia estados cuando algo falla o se recupera.
  #
  #  - Un fallo de familia `connection` (llave, cuenta, número) pasa la conexión a «Con error». Los interruptores no se
  #    tocan: al recuperarse la conexión, el canal vuelve a funcionar solo.
  #  - Un fallo de familia `template` apaga **solo ese tipo de mensaje** y marca su plantilla; hay que volver a
  #    encenderlo a mano cuando la plantilla esté aprobada.
  #  - Los fallos del destinatario o transitorios (límites, red) no cambian nada.
  #
  # **Un correo por cambio de estado** a los super admin activos: `problem_notified_at` marca que el problema vigente ya se
  # avisó, y se limpia al recuperarse (así un problema nuevo vuelve a avisar). Con solo variables de entorno
  # (`managed = false`) no hay dónde guardar el estado y no se hace nada. Nada de esto debe romper el envío original.
  class Health
    TEMPLATE_STATUS_BY_REASON = { "template_missing" => "not_found", "template_variables" => "incompatible", "template_paused" => "rejected" }.freeze

    def self.record_failure(kind, failure) = new.record_failure(kind, failure)

    def self.connection_recovered! = new.connection_recovered!

    def self.template_recovered!(type) = new.template_recovered!(type)

    def self.template_unusable!(kind, status:, detail:) = new.template_unusable!(kind, status: status, detail: detail)

    def record_failure(kind, failure)
      return unless failure && Whatsapp::Config.current.panel?

      case failure.family
      when :connection then connection_failed(failure)
      when :template then template_failed(kind, failure)
      end
    rescue StandardError => e
      Rails.logger.error("[Whatsapp::Health] #{e.class}: #{e.message}")
    end

    # Un envío real salió bien: la conexión y la plantilla de ese tipo funcionan, así que se limpian sus errores.
    def self.record_success(kind) = new.record_success(kind)

    def record_success(kind)
      return unless Whatsapp::Config.current.panel?

      connection_recovered!
      type = WhatsappMessageType.find_by(kind: kind.to_s)
      template_recovered!(type) if type
    rescue StandardError => e
      Rails.logger.error("[Whatsapp::Health] #{e.class}: #{e.message}")
    end

    # La conexión se verificó bien: sale del error y vuelve a poder avisar si falla otra vez.
    def connection_recovered!
      connection = WhatsappConnection.current
      return unless connection.error? || connection.problem_notified_at

      connection.with_lock do
        connection.update!(status: "connected", error_code: nil, error_message: nil, last_verified_at: Time.current, problem_notified_at: nil)
      end
    end

    def template_recovered!(type)
      type.update!(problem_notified_at: nil) if type.problem_notified_at
    end

    # Una verificación encontró la plantilla inutilizable (`status`: pending, rejected, not_found o incompatible). Si el tipo
    # estaba encendido se apaga solo y se avisa; conserva el detalle que dio Meta.
    def template_unusable!(kind, status:, detail:)
      reason = TEMPLATE_STATUS_BY_REASON.key(status) || "template_paused"
      template_failed(kind, Whatsapp::GraphClient::Failure.new(family: :template, reason: reason), status: status, detail: detail)
    end

    private

    def connection_failed(failure)
      connection = WhatsappConnection.current
      detail = reason_text(failure.reason)
      since = Time.current
      first = false

      connection.with_lock do
        first = connection.problem_notified_at.nil?
        connection.update!(status: "error", error_code: failure.code&.to_s, error_message: detail, last_verified_at: since,
                           problem_notified_at: connection.problem_notified_at || since)
      end
      return unless first

      WhatsappEvent.log!(action: "connection_error", target: "connection", result: "failed", meta_code: failure.code, data: { reason: failure.reason })
      notify(problem: "connection", target: "connection", detail: detail, since: since)
    end

    def template_failed(kind, failure, status: nil, detail: nil)
      type = WhatsappMessageType.find_by(kind: kind.to_s)
      return unless type&.uses_template?

      detail ||= reason_text(failure.reason)
      status ||= TEMPLATE_STATUS_BY_REASON.fetch(failure.reason, "rejected")
      since = Time.current
      auto_off = false

      type.with_lock do
        auto_off = type.enabled? && type.problem_notified_at.nil?
        type.update!(template_status: status, template_detail: detail,
                     template_checked_at: since, enabled: false,
                     problem_notified_at: auto_off ? since : type.problem_notified_at)
      end
      return unless auto_off

      WhatsappEvent.log!(action: "auto_off", target: type.kind, result: "failed", meta_code: failure.code, data: { reason: failure.reason })
      notify(problem: "template", target: type.kind, detail: detail, since: since)
    end

    # Un correo a cada super admin activo; el fallo de uno no detiene a los demás.
    def notify(problem:, target:, detail:, since:)
      users = User.super_admin.where(active: true).where.not(email: [ nil, "" ]).to_a
      delivered = users.count do |user|
        ResendMailer.whatsapp_alert(user: user, problem: problem, target: target, detail: detail, since: since).present?
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Health] correo a user=#{user.id}: #{e.class}")
        false
      end
      WhatsappEvent.log!(action: "alert_sent", target: target, result: delivered.positive? ? "ok" : "failed", data: { recipients: users.size, delivered: delivered })
    end

    def reason_text(reason)
      I18n.t("whatsapp_admin.reasons.#{reason}", default: I18n.t("whatsapp_admin.reasons.unknown"))
    end
  end
end
