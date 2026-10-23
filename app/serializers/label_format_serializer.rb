# Formato de etiqueta, común (catálogo, `id` "std:<clave>") o propio de la empresa (`id` numérico), con la misma forma.
class LabelFormatSerializer
  SMALL_HEIGHT_MM = 25
  SMALL_WIDTH_MM = 38

  def initialize(format)
    @format = format
  end

  def as_json(*)
    {
      id: @format.id,
      name: @format.name,
      custom: @format.custom?,
      kind: @format.kind,
      page_width_mm: number(@format.page_width_mm),
      page_height_mm: number(@format.page_height_mm),
      columns: @format.columns,
      rows: @format.rows,
      label_width_mm: number(@format.label_width_mm),
      label_height_mm: number(@format.label_height_mm),
      margin_top_mm: number(@format.margin_top_mm),
      margin_left_mm: number(@format.margin_left_mm),
      gap_x_mm: number(@format.gap_x_mm),
      gap_y_mm: number(@format.gap_y_mm),
      labels_per_page: @format.labels_per_page,
      small: small?(@format)
    }
  end

  # Etiquetas chicas: el nombre y el precio nacen apagados para no quitarle espacio al código (spec 035, clarificación 2).
  def self.small?(format)
    format.label_height_mm.to_d < SMALL_HEIGHT_MM || format.label_width_mm.to_d < SMALL_WIDTH_MM
  end

  private

  def small?(format) = self.class.small?(format)

  # Milímetros como número (sin ceros de más): 38.1, 21.2, 0.
  def number(value)
    decimal = value.to_d
    decimal == decimal.to_i ? decimal.to_i : decimal.to_f
  end
end
