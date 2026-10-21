module Reports
  # Periodo anterior de un reporte: mismo número de días, termina el día antes de que empiece el vigente.
  module Comparison
    def self.previous_range(range)
      from = range.first.to_date
      to   = range.last.to_date
      days = (to - from).to_i + 1
      (from - days).beginning_of_day..(from - 1).end_of_day
    end
  end
end
