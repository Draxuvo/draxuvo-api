module Alerts
  # Arma las alertas activas de una empresa (spec 045): consulta las fuentes cuyo módulo está activo, separa las
  # pospuestas, ordena por severidad y tiempo, y olvida las posposiciones de elementos que ya avanzaron.
  class Collector
    Result = Struct.new(:results, :snoozed, keyword_init: true)

    SOURCES = [
      Sources::KitchenWait, Sources::KitchenPreparing, Sources::WorkOrderStalled, Sources::TableOpen, Sources::LowStock
    ].freeze

    # Tipos de alerta cuyo módulo está activo en la empresa (la UI oculta el resto de la configuración).
    def self.applicable_kinds(company)
      SOURCES.select { |source| company.module_active?(source.module_key) }.map { |source| source::KIND }
    end

    def initialize(company, now: Time.current)
      @company = company
      @now = now
    end

    def call
      alerts = sources.flat_map { |source| source.new(@company, Thresholds.new(@company), @now).call }
      snoozes = active_snoozes
      forget_stale(alerts, snoozes)

      active, snoozed = alerts.partition { |alert| !snoozes.key?(alert.snooze_key) }
      Result.new(results: sort(active), snoozed: sort(snoozed).map { |alert| [ alert, snoozes.fetch(alert.snooze_key) ] })
    end

    private

    def sources
      SOURCES.select { |source| @company.module_active?(source.module_key) }
    end

    def active_snoozes
      @company.alert_snoozes.active.includes(:user).index_by { |snooze| [ snooze.kind, snooze.subject_key ] }
    end

    # Una posposición solo vale mientras el elemento siga con la alerta: al avanzar (o al vencer) se borra.
    def forget_stale(alerts, snoozes)
      live = alerts.map(&:snooze_key)
      stale = @company.alert_snoozes.expired.pluck(:id) + snoozes.reject { |key, _| live.include?(key) }.values.map(&:id)
      @company.alert_snoozes.where(id: stale).delete_all if stale.any?
    end

    # Primero las críticas y, dentro de cada severidad, las que más llevan.
    def sort(alerts)
      alerts.sort_by { |alert| [ alert.critical? ? 0 : 1, -alert.minutes.to_i, alert.subject[:label].to_s ] }
    end
  end
end
