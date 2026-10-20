# Un cambio de módulo de una empresa hecho por el super admin (spec 017): quién, qué módulo, estado nuevo y cuándo.
# Solo se inserta; no hay pantalla para consultarlo.
class ModuleChange < ApplicationRecord
  belongs_to :company
  belongs_to :actor, class_name: "User"

  validates :module, inclusion: { in: ->(_) { Plan::MODULES.map(&:to_s) } }
  validates :enabled, inclusion: { in: [ true, false ] }
end
