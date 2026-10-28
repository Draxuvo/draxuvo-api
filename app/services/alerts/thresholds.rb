module Alerts
  # Tiempos límite vigentes de una empresa (spec 045): lo que el negocio configuró o, si no, los valores por omisión.
  class Thresholds
    def initialize(company)
      @setting = AlertSetting.for(company)
    end

    # Minutos de `kind`; en las alertas de comanda depende del tipo de la estación.
    def minutes(kind, station_kind = nil) = @setting.minutes_for(kind, station_kind)
  end
end
