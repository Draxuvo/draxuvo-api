# app/models/unit.rb
class Unit < ApplicationRecord
  # Catálogo de referencia (spec 044): lo usan la migración, los seeds, el arranque y el alta de empresas.
  # Los tipos de producto iniciales (`ProductTypes::Defaults`) apuntan a estas claves.
  CATALOG = [
    { key: "pza",  name: "Pieza",     group: "cantidad", position: 1 },
    { key: "hr",   name: "Hora",      group: "tiempo",   position: 2 },
    { key: "kg",   name: "Kilogramo", group: "peso",     position: 3 },
    { key: "lt",   name: "Litro",     group: "volumen",  position: 4 },
    { key: "mts",  name: "Metro",     group: "longitud", position: 5 },
    { key: "serv", name: "Servicio",  group: "servicio", position: 6 },
    { key: "g",    name: "Gramo",     group: "peso",     position: 7 },
    { key: "ml",   name: "Mililitro", group: "volumen",  position: 8 },
    { key: "paq",  name: "Paquete",   group: "cantidad", position: 9 }
  ].freeze

  # Crea las unidades del catálogo que falten. Idempotente y segura con arranques simultáneos: no duplica
  # ni modifica las que ya existen (aunque se hayan editado).
  def self.ensure_catalog!
    return if where(key: CATALOG.map { |unit| unit[:key] }).count == CATALOG.size

    insert_all(CATALOG, unique_by: :key)
  end

  validates :key,  presence: true, uniqueness: true
  validates :name, presence: true
  validates :group, presence: true

  scope :ordered, -> { order(:group, :position, :key) }
end
