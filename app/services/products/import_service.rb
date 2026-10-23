module Products
  # Importa productos desde Excel o CSV (spec 034: por lotes, con códigos de barras, movimientos de stock y avance).
  class ImportService
    HEADER_KEYS = %w[sku name description category price unit_cost stock min_stock available product_type unit icon barcodes].freeze
    BATCH_SIZE = 200

    # `errors` guarda hasta ProductImport::MAX_ERRORS filas; `errors_total` cuenta todas.
    Result = Struct.new(:created, :updated, :unchanged, :errors, :errors_total, :processed, keyword_init: true)

    # `allow_icon`: solo administrador y dueño asignan iconos; con otro rol la columna `icon` se ignora (spec 026).
    # `user`: quien importa, para los movimientos de stock. `on_progress`: se llama con el Result parcial tras cada lote.
    def initialize(company, file, allow_icon: false, user: nil, on_progress: nil, batch_size: BATCH_SIZE)
      @company = company
      @file = file
      @allow_icon = allow_icon
      @user = user
      @on_progress = on_progress
      @batch_size = batch_size
    end

    # Filas de datos del archivo (sin encabezado, vacías ni notas), para validar el tamaño antes de encolar.
    def self.count_rows(file)
      new(nil, file).send(:data_rows).size
    end

    def call
      @result = Result.new(created: 0, updated: 0, unchanged: 0, errors: [], errors_total: 0, processed: 0)
      @headers_seen = {}
      @codes_in_file = {}
      rows = data_rows
      rows.each_slice(@batch_size) do |batch|
        process_batch(batch)
        @result.processed += batch.size
        @on_progress&.call(@result)
      end
      @result
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

          # Sin tipo explícito Excel convierte los códigos en números y pierde los ceros iniciales (spec 034).
          sample = HEADER_KEYS.map { |k| t.call("sample.#{k}") }
          sheet.add_row sample, types: HEADER_KEYS.map { |k| %w[sku barcodes].include?(k) ? :string : nil }

          sheet.add_row [], style: note_style
          sheet.add_row [ "# #{t.call('hint')}" ], style: note_style

          sheet.column_widths 15, 30, 35, 20, 12, 12, 10, 12, 12, 16, 12, 12, 28
        end
      end

      package.to_stream.read
    end

    private

    # [[número de fila, hash de atributos]] de las filas con datos.
    def data_rows
      spreadsheet = open_spreadsheet
      sheet = spreadsheet.sheet(0)
      return [] unless sheet.last_row

      lookup = self.class.header_lookup
      headers = sheet.row(1).map { |h| lookup[self.class.normalize_header(h)] || self.class.normalize_header(h) }
      (2..sheet.last_row).filter_map do |i|
        row = sheet.row(i)
        next if row.compact.empty?
        next if row.first.to_s.start_with?("#") # fila de nota de la plantilla

        [ i, headers.zip(row).to_h.slice(*HEADER_KEYS) ]
      end
    end

    def process_batch(batch)
      skus = batch.filter_map { |_, attrs| Barcodes.normalize(attrs["sku"]) }
      @products = @company.products.includes(:product_type, :barcodes).where(sku: skus).index_by(&:sku)
      codes = batch.flat_map { |_, attrs| Barcodes.split(attrs["barcodes"]) }
      @owners = @company.product_barcodes.where(code: codes).pluck(:code, :product_id).to_h

      snapshot = [ @result.dup.tap { |r| r.errors = r.errors.dup }, @codes_in_file.dup ]
      begin
        run_batch(batch, safe: false)
      rescue StandardError
        # Una falla inesperada de la base aborta el lote entero: se deshace y se repite fila por fila con puntos de guardado.
        @result, @codes_in_file = snapshot
        run_batch(batch, safe: true)
      end
    end

    def run_batch(batch, safe:)
      entries = []
      barcode_rows = []
      Product.transaction do
        batch.each { |row_number, attrs| process_row(row_number, attrs, entries, barcode_rows, safe: safe) }
        now = Time.current
        ProductBarcode.insert_all!(barcode_rows.map { |row| row.merge(created_at: now, updated_at: now) }) if barcode_rows.any?
        Stock::RecordMovements.call(company: @company, user: @user, entries: entries)
      end
    end

    def process_row(row_number, attrs, entries, barcode_rows, safe:)
      sku = Barcodes.normalize(attrs["sku"])
      return add_error(row_number, nil, I18n.t("products.import.sku_required")) if sku.blank?

      outcome = safe ? import_row_safely(row_number, sku, attrs, entries, barcode_rows) : import_row(row_number, sku, attrs, entries, barcode_rows)
      outcome.is_a?(String) ? add_error(row_number, sku, outcome) : @result[outcome] += 1
    end

    # Con punto de guardado: un error de la base solo descarta esa fila.
    def import_row_safely(row_number, sku, attrs, entries, barcode_rows)
      entries_size = entries.size
      rows_size = barcode_rows.size
      outcome = nil
      Product.transaction(requires_new: true) do
        outcome = import_row(row_number, sku, attrs, entries, barcode_rows)
        raise ActiveRecord::Rollback if outcome.is_a?(String)
      end
      if outcome.is_a?(String)
        entries.slice!(entries_size..)
        barcode_rows.slice!(rows_size..)
      end
      outcome
    rescue StandardError => e
      entries.slice!(entries_size..)
      barcode_rows.slice!(rows_size..)
      e.message
    end

    # Devuelve :created, :updated, :unchanged o un texto con el error de la fila.
    def import_row(_row_number, sku, attrs, entries, barcode_rows)
      existing = @products[sku]
      was_new = existing.nil?
      product = existing || @company.products.new(sku: sku)
      codes = Barcodes.split(attrs["barcodes"])
      code, owner = conflicting_code(codes, product, sku, @owners)
      return I18n.t("products.barcodes.taken", barcode: code, product: owner) if code

      desired_stock = parse_decimal(attrs["stock"])
      product.assign_attributes(
        name:        attrs["name"].to_s.strip.presence || product.name,
        description: attrs["description"].to_s.strip.presence,
        category:    attrs["category"].to_s.strip.presence,
        price:       parse_decimal(attrs["price"]),
        unit_cost:   parse_decimal(attrs["unit_cost"]),
        min_stock:   parse_decimal(attrs["min_stock"]),
        available:   parse_boolean(attrs["available"])
      )
      # El stock de un producto nuevo se asigna solo para clasificarlo; el stock real entra como movimiento.
      product.stock = desired_stock || 0 if was_new
      assign_type_and_unit(product, attrs)
      assign_icon(product, attrs)
      product.stock = 0 if was_new

      changed = product.changed? || was_new
      return product.errors.full_messages.join(", ") unless product.save

      delta = stock_delta(product, desired_stock, was_new)
      return delta if delta.is_a?(String)

      known = was_new ? [] : product.barcodes.map(&:code)
      (codes - known).each do |new_code|
        barcode_rows << { company_id: @company.id, product_id: product.id, code: new_code }
        changed = true
      end
      codes.each { |c| @codes_in_file[c] = sku }
      if delta
        entries << { product: product, delta: delta, type: was_new ? :entry : :adjustment, note: I18n.t("products.import.stock_note") }
        changed = true
      end

      was_new ? :created : (changed ? :updated : :unchanged)
    end

    # Primer código de la fila que ya es de otro producto (de la base o de una fila anterior del archivo):
    # [código, nombre del otro producto], o nil.
    def conflicting_code(codes, product, sku, owners)
      codes.each do |code|
        owner_id = owners[code]
        return [ code, @company.products.find_by(id: owner_id)&.name ] if owner_id && owner_id != product.id
        file_sku = @codes_in_file[code]
        return [ code, @company.products.find_by(sku: file_sku)&.name || file_sku ] if file_sku && file_sku != sku
      end
      nil
    end

    # Diferencia de stock a registrar: nil si no aplica (tipo sin existencia o sin cambio), texto si es inválida.
    def stock_delta(product, desired, was_new)
      return nil if desired.nil? || !product.counted?

      delta = desired - (was_new ? 0 : product.stock.to_d)
      return nil if delta.zero?
      return I18n.t("activerecord.errors.messages.integer_only") if !product.fractional? && delta != delta.round

      delta
    end

    def add_error(row_number, sku, message)
      @result.errors_total += 1
      return unless @result.errors.size < ProductImport::MAX_ERRORS

      entry = { row: row_number, error: message }
      entry[:sku] = sku if sku.present?
      @result.errors << entry
    end

    # Tipo por nombre y unidad por clave o nombre (spec 016, FR-016). Sin tipo, o con uno que no existe, se
    # clasifica con la regla de los tipos iniciales.
    def assign_type_and_unit(product, attrs)
      name = attrs["product_type"].to_s.strip
      type = @company.product_types.find_by("lower(name) = ?", name.downcase) if name.present?
      product.product_type = type || (product.product_type if name.blank?) || classify(product)
      product.available = true unless product.product_type.sellable

      unit = attrs["unit"].to_s.strip
      return if unit.blank?

      found = Unit.where("lower(key) = :u OR lower(name) = :u", u: unit.downcase).first
      product.unit_key = found&.key
    end

    # Misma regla que `ProductTypes::Defaults.classify`, con los tipos de la empresa leídos una sola vez.
    def classify(product)
      @types_by_kind ||= begin
        ProductTypes::Defaults.create_missing(@company)
        @company.product_types.where.not(kind: nil).index_by(&:kind)
      end
      @types_by_kind[ProductTypes::Defaults.kind_for(@company, product)] || (@first_type ||= @company.product_types.active.ordered.first)
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
