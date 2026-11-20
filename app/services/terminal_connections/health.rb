module TerminalConnections
  # Salud de una conexión con un proveedor de terminal (spec 069, FR-030, research R13). Un fallo de familia `connection`
  # (token vencido, revocado o ilegible) pasa la conexión a «Con error» y avisa por correo a dueño y administradores
  # **una vez por cambio de estado** (`problem_notified_at`). Nada de esto debe romper la operación que lo detectó.
  class Health
    def self.failed!(connection, failure) = new(connection).failed!(failure)
    def self.recovered!(connection) = new(connection).recovered!

    def initialize(connection)
      @connection = connection
    end

    def failed!(failure)
      return unless failure.respond_to?(:connection?) && failure.connection?

      notify = false
      @connection.with_lock do
        next if @connection.disconnected?

        notify = @connection.problem_notified_at.nil?
        @connection.update!(status: "error", error_code: failure.reason.to_s.first(60),
                            error_message: I18n.t("terminal_connection.problems.#{failure.reason}", default: I18n.t("terminal_connection.problems.generic")),
                            problem_notified_at: @connection.problem_notified_at || Time.current)
      end
      TerminalEvent.log!(:connection_error, connection: @connection, reason: failure.reason.to_s)
      notify_owners(failure.reason) if notify
    rescue StandardError => e
      Rails.logger.error("[TerminalConnections::Health] #{e.class}: #{e.message}")
    end

    def recovered!
      return unless @connection.error? || @connection.problem_notified_at

      @connection.update!(status: "connected", error_code: nil, error_message: nil, problem_notified_at: nil)
    end

    # Dueño y administradores activos de la empresa (nada en demo: ResendMailer ya lo simula).
    def notify_owners(reason)
      company = @connection.company
      company.user_companies.includes(:user).where(role: %i[owner admin]).find_each do |membership|
        user = membership.user
        next unless user&.active? && user.email.present?

        ResendMailer.terminal_connection_problem(user: user, company_name: company.name, provider: @connection.provider,
                                                 reason: reason.to_s)
      end
    end
  end
end
