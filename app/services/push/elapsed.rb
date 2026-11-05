module Push
  # Tiempo transcurrido de una alerta con el mismo formato que la pantalla de Alertas de la app (`formatElapsed`):
  # «45 min», «3 h 10 min», «15 d», «2 d 4 h». Sin esto el aviso decía «sin avance desde hace 21652 min».
  module Elapsed
    module_function

    def format(minutes, locale:)
      total = [ minutes.to_f.round, 0 ].max
      scope = { scope: "push.time", locale: locale }
      return I18n.t(:minutes, count: total, **scope) if total < 60

      if total < 1440
        hours, rest = total.divmod(60)
        return rest.zero? ? I18n.t(:hours, count: hours, **scope) : I18n.t(:hours_minutes, hours: hours, minutes: rest, **scope)
      end

      days, rest = total.divmod(1440)
      hours = rest / 60
      hours.zero? ? I18n.t(:days, count: days, **scope) : I18n.t(:days_hours, days: days, hours: hours, **scope)
    end
  end
end
