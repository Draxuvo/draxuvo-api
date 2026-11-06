# Un cambio de «Cobro solo por jefes» de una empresa hecho por el super admin (spec 058): quién, el valor nuevo y cuándo.
# Solo se inserta; el valor anterior es el contrario de `enabled` (solo se registra cuando cambia).
class ChargePolicyChange < ApplicationRecord
  belongs_to :company
  belongs_to :actor, class_name: "User"

  validates :enabled, inclusion: { in: [ true, false ] }
end
