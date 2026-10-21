module Products
  class ImportService
    HEADER_KEYS = %w[sku name description category price unit_cost stock min_stock available product_type unit icon].freeze

    Result = Struct.new(:created, :updated, :errors, keyword_init: true)

    # `allow_icon`: solo administrador y dueño asignan iconos; con otro rol la columna `icon` se ignora (spec 026).
    def initialize(company, file, allow_icon: false)
      @company = company
      @file    = file
      @allow_icon = allow_icon
    end

    def call
      spreadsheet = open_spreadsheet
      created = 0
      updated = 0
      row_errors = []

      rows = spreadsheet.sheet(0)
      lookup  = self.class.header_lookup
      headers = rows.row(1).map { |h| lookup[self.class.normalize_header(h)] || self.class.normalize_header(h) }

      (2..rows.last_row).each do |i|
        row = rows.row(i)
        next if row.compact.empty?
        next if row.first.to_s.start_with?("#") # fila de nota de la plantilla

        attrs = headers.zip(row).to_h.slice(*HEADER_KEYS)
        sku   = attrs["sku"].to_s.strip

        if sku.blank?
          row_errors << { row: i, error: I18n.t("products.import.sku_required") }
          next
        end

        product = @company.products.find_or_initialize_by(sku: sku)
        was_new = product.new_record?

        product.assign_attributes(
          name:        attrs["name"].to_s.strip.presence || product.name,
          description: attrs["description"].to_s.strip.presence,
          category:    attrs["category"].to_s.strip.presence,
          price:       parse_decimal(attrs["price"]),
          unit_cost:   parse_decimal(attrs["unit_cost"]),
          stock:       parse_decimal(attrs["stock"]) || (was_new ? 0 : product.stock),
          min_stock:   parse_decimal(attrs["min_stock"]),
          available:   parse_boolean(attrs["available"])
        )
        assign_type_and_unit(product, attrs)
        assign_icon(product, attrs)

        if product.save
          was_new ? created += 1 : updated += 1
        else
          row_errors << { row: i, sku: sku, error: product.errors.full_messages.join(", ") }
        end
      rescue StandardError => e
        row_errors << { row: i, error: e.message }
      end

      Result.new(created: created, updated: updated, errors: row_errors)
    end

    # Texto de encabezado sin acentos, en minúsculas y con guiones bajos ("COSTO UNITARIO" → "costo_unitario").
    def self.normalize_header(value)
      I18n.transliterate(value.to_s).strip.downcase.tr(" ", "_")
    end

    # Encabezado normalizado → clave. Acepta las claves en inglés y los rótulos de la plantilla en
    # cada idioma, para que la plantilla descargada se pueda volver a importar.
    def self.header_lookup
      labels = I18n.available_locales.flat_map do |locale|
        HEADER_KEYS.map { |key| [ normalize_header(I18n.t("products.import.headers.#{key}", locale: locale)), key ] }
      end
      labels.to_h.merge(HEADER_KEYS.index_by { |key| normalize_header(key) })
    end

    def self.generate_template
      t = ->(key) { I18n.t("products.import.#{key}") }

      package = Axlsx::Package.new
      wb      = package.workbook

      wb.styles do |s|
        header_style = s.add_style bg_color: "1F4E79", fg_color: "FFFFFF", b: true, sz: 11,
                                   alignment: { horizontal: :center }
        note_style   = s.add_style fg_color: "7F7F7F", i: true, sz: 9

        wb.add_worksheet(name: t.call("template_sheet")) do |sheet|
          headers = HEADER_KEYS.map { |k| t.call("headers.#{k}") }
          sheet.add_row headers, style: header_style

          sample = HEADER_KEYS.map { |k| t.call("sample.#{k}") }
          sheet.add_row sample

          sheet.add_row [], style: note_style
          sheet.add_row [ "# #{t.call('hint')}" ], style: note_style

          sheet.column_widths 15, 30, 35, 20, 12, 12, 10, 12, 12, 16, 12, 12
        end
      end

      package.to_stream.read
    end

    private

    # Tipo por nombre y unidad por clave o nombre (spec 016, FR-016). Sin tipo, o con uno que no existe, se
    # clasifica con la regla de los tipos iniciales.
    def assign_type_and_unit(product, attrs)
      name = attrs["product_type"].to_s.strip
      type = @company.product_types.find_by("lower(name) = ?", name.downcase) if name.present?
      product.product_type = type || (product.product_type if name.blank?) || ProductTypes::Defaults.classify(@company, product)
      product.available = true unless product.product_type.sellable

      unit = attrs["unit"].to_s.strip
      return if unit.blank?

      found = Unit.where("lower(key) = :u OR lower(name) = :u", u: unit.downcase).first
      product.unit_key = found&.key
    end

    # Clave inválida o sin permiso: se deja el icono como estaba (sin error de fila).
    def assign_icon(product, attrs)
      key = attrs["icon"].to_s.strip.downcase
      product.icon = key if @allow_icon && ProductIcons.valid?(key)
    end

    def open_spreadsheet
      path = @file.respond_to?(:path) ? @file.path : @file.tempfile.path
      ext  = File.extname(@file.respond_to?(:original_filename) ? @file.original_filename : path).downcase

      case ext
      when ".xlsx" then Roo::Excelx.new(path)
      when ".xls"  then Roo::Excel.new(path)
      when ".csv"  then Roo::CSV.new(path)
      else raise ApiErrors::BadRequestError.new(message: I18n.t("products.import.unsupported_format"))
      end
    end

    def parse_decimal(val)
      return nil if val.nil? || val.to_s.strip.empty?
      val.to_s.gsub(/[^\d.]/, "").to_d
    end

    def parse_integer(val)
      return nil if val.nil? || val.to_s.strip.empty?
      val.to_s.gsub(/[^\d]/, "").to_i
    end

    def parse_boolean(val)
      return true if val.nil?
      %w[true 1 yes si sí].include?(val.to_s.strip.downcase)
    end
  end
end
