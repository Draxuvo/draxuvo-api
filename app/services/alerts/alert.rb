module Alerts
  # Una alerta activa. No se guarda: se deriva del estado actual del negocio (spec 045, research R1).
  # `subject_key` identifica el elemento y su origen; es lo que se posponen y lo que desaparece al avanzar el elemento.
  Alert = Struct.new(:kind, :subject_key, :severity, :minutes, :threshold_minutes, :subject, :owner, :total, :stock, :min_stock,
                     keyword_init: true) do
    def id = "#{kind}:#{subject_key}"
    def snooze_key = [ kind, subject_key ]
    def critical? = severity == "critical"
  end
end
