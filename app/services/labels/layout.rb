module Labels
  # Dónde cae cada etiqueta en el papel (spec 035). Las etiquetas se llenan por filas, de izquierda a derecha y de arriba
  # a abajo; en un rollo cada etiqueta es una página del tamaño de la etiqueta. Todo en puntos de PDF (72 por pulgada).
  class Layout
    Slot = Struct.new(:page, :column, :row, :x, :y, :width, :height, keyword_init: true)

    MM_TO_PT = 72.0 / 25.4

    def self.points(mm) = (mm.to_f * MM_TO_PT).round(2)

    attr_reader :format

    def initialize(format)
      @format = format
    end

    def page_width = self.class.points(format.page_width_mm)
    def page_height = self.class.points(format.page_height_mm)
    def label_width = self.class.points(format.label_width_mm)
    def label_height = self.class.points(format.label_height_mm)
    def per_page = format.columns * format.rows
    def roll? = format.kind == "roll"

    # Etiqueta número `index` (0 es la primera), con `start_position` (1 a per_page) como la primera libre de la
    # primera hoja. `x`, `y` son la esquina inferior izquierda de la etiqueta en el sistema de coordenadas de Prawn.
    def slot(index, start_position: 1)
      return Slot.new(page: index, column: 0, row: 0, x: 0, y: 0, width: label_width, height: label_height) if roll?

      absolute = index + (start_position.to_i - 1)
      page, within = absolute.divmod(per_page)
      row, column = within.divmod(format.columns)
      x = self.class.points(format.margin_left_mm.to_f + (column * (format.label_width_mm.to_f + format.gap_x_mm.to_f)))
      top = self.class.points(format.margin_top_mm.to_f + (row * (format.label_height_mm.to_f + format.gap_y_mm.to_f)))
      Slot.new(page: page, column: column, row: row, x: x, y: (page_height - top - label_height).round(2),
               width: label_width, height: label_height)
    end

    # Cuántas páginas ocupan `count` etiquetas desde `start_position`.
    def pages_for(count, start_position: 1)
      return count if roll?

      ((count + start_position.to_i - 1).to_f / per_page).ceil
    end
  end
end
