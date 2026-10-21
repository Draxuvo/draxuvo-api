module Reports
  # Clave con la que los reportes agrupan una fecha: día, semana ISO, mes (por defecto) o año.
  module PeriodKey
    GROUPS = %w[day week month year].freeze

    def self.call(time, group_by)
      case group_by
      when "day"  then time.strftime("%Y-%m-%d")
      when "week" then time.strftime("%G-W%V")
      when "year" then time.strftime("%Y")
      else             time.strftime("%Y-%m")
      end
    end
  end
end
