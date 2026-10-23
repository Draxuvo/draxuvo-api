module Labels
  # Formatos de etiqueta comunes (spec 035), leídos de config/label_formats.yml. Se identifican como `std:<key>`;
  # no se editan ni se borran y los ven todas las empresas.
  class Catalog
    PREFIX = "std:".freeze
    FILE = Rails.root.join("config/label_formats.yml").freeze

    Format = Struct.new(:key, :paper, :page_width_mm, :page_height_mm, :columns, :rows, :label_width_mm, :label_height_mm,
                        :margin_top_mm, :margin_left_mm, :gap_x_mm, :gap_y_mm, keyword_init: true) do
      def id = "#{PREFIX}#{key}"
      def custom? = false
      def kind = paper == "roll" ? "roll" : "sheet"
      def labels_per_page = columns * rows

      def name
        size = "#{format("%g", label_width_mm)} × #{format("%g", label_height_mm)} mm"
        return I18n.t("labels.formats.roll", size: size) if paper == "roll"

        I18n.t("labels.formats.sheet", paper: I18n.t("labels.papers.#{paper}"), count: labels_per_page, size: size)
      end
    end

    class << self
      def all
        @all ||= YAML.safe_load_file(FILE).map { |attrs| Format.new(**attrs.symbolize_keys) }.freeze
      end

      def find(id)
        key = id.to_s.delete_prefix(PREFIX)
        all.find { |format| format.key == key } if id.to_s.start_with?(PREFIX)
      end
    end
  end
end
