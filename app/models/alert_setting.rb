# Tiempos límite, hora del resumen y zona horaria de las alertas de una empresa (spec 045).
# `thresholds` guarda solo lo que el negocio cambió; lo demás sale de DEFAULTS.
class AlertSetting < ApplicationRecord
  belongs_to :company

  DEFAULTS = {
    "kitchen_wait" => { "kitchen" => 10, "bar" => 5, "other" => 10 },
    "kitchen_preparing" => { "kitchen" => 25, "bar" => 10, "other" => 25 },
    "table_open" => 90,
    "work_order_stalled" => 1440
  }.freeze
  # Alertas de comanda: un tiempo por tipo de estación.
  PER_STATION = %w[kitchen_wait kitchen_preparing].freeze
  MINUTES = (1..10_080).freeze

  validates :summary_hour, inclusion: { in: 0..23 }
  validate :time_zone_exists
  validate :thresholds_in_catalog

  def self.for(company) = company.alert_setting || AlertSetting.new(company: company)

  # Valores vigentes con la misma forma que DEFAULTS.
  def effective
    DEFAULTS.to_h do |kind, default|
      value = thresholds.to_h[kind]
      [ kind, default.is_a?(Hash) ? default.merge(value.is_a?(Hash) ? value : {}) : (value || default) ]
    end
  end

  # Minutos del límite de `kind`; en comandas, según el tipo de estación (si no es válido, "other").
  def minutes_for(kind, station_kind = nil)
    value = effective.fetch(kind.to_s)
    return value unless value.is_a?(Hash)

    value.fetch(Station::KINDS.include?(station_kind.to_s) ? station_kind.to_s : "other")
  end

  # Mezcla un cambio parcial (misma forma que `thresholds`) con lo guardado, sin tocar el resto.
  def merge_thresholds(partial)
    current = thresholds.to_h.deep_dup
    partial.to_h.each do |kind, value|
      current[kind.to_s] = value.is_a?(Hash) ? current.fetch(kind.to_s, {}).to_h.merge(value.stringify_keys) : value
    end
    self.thresholds = current
  end

  private

  def time_zone_exists
    errors.add(:time_zone, :inclusion) unless ActiveSupport::TimeZone[time_zone.to_s]
  end

  def thresholds_in_catalog
    raw = thresholds
    return errors.add(:thresholds, :invalid) unless raw.is_a?(Hash)

    raw.each do |kind, value|
      default = DEFAULTS[kind.to_s]
      next errors.add(:thresholds, :inclusion, value: kind) if default.nil?

      if default.is_a?(Hash)
        valid = value.is_a?(Hash) && value.keys.all? { |station| default.key?(station.to_s) } && value.values.all? { |minutes| minutes?(minutes) }
        errors.add(:thresholds, :invalid) unless valid
      else
        errors.add(:thresholds, :invalid) unless minutes?(value)
      end
    end
  end

  def minutes?(value) = value.is_a?(Integer) && MINUTES.cover?(value)
end
