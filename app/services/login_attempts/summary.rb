# Resumen de «Accesos» (spec 073): entradas y fallos de hoy (hora de México) y las IP y correos con más fallos de la
# última hora, para ver a alguien probando contraseñas o a un cliente que no logra entrar.
module LoginAttempts
  class Summary
    WINDOW_MINUTES = 60
    TOP = 5

    def self.call = new.call

    def call
      recent_failures = LoginAttempt.failures.since(WINDOW_MINUTES.minutes.ago)
      {
        today: today,
        window_minutes: WINDOW_MINUTES,
        top_ips: top(recent_failures.where.not(ip: nil), :ip).map { |ip, count| { ip: ip.to_s, failures: count } },
        top_emails: top(recent_failures, :email).map { |email, count| { email: email, failures: count } }
      }
    end

    private

    def today
      start = Time.find_zone!(LoginAttempt::ZONE).now.beginning_of_day
      counts = LoginAttempt.since(start).group(:result).count
      success = counts.fetch("success", 0)
      { success: success, failures: counts.values.sum - success }
    end

    def top(scope, column)
      scope.group(column).order(Arel.sql("COUNT(*) DESC"), column).limit(TOP).count
    end
  end
end
