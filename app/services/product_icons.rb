# Catálogo cerrado de iconos de producto (spec 026): claves en config/product_icons.yml, agrupadas por giro.
module ProductIcons
  # Icono sugerido de los tipos iniciales, por `kind` y giro de la empresa (ProductTypes::Defaults).
  DEFAULTS = {
    "order" => { "sold" => "utensils", "counted_sold" => "cup", "supply" => "box" },
    "service" => { "sold" => "wrench", "counted_sold" => "gear", "supply" => "box" }
  }.freeze

  def self.groups = (@groups ||= YAML.load_file(Rails.root.join("config/product_icons.yml")).freeze)

  def self.keys = (@keys ||= groups.values.flatten.freeze)

  def self.valid?(key) = keys.include?(key)

  def self.default_for(kind, order_mode = "order") = DEFAULTS.dig(order_mode.to_s, kind.to_s)
end
