require "prawn"

module Labels
  # PDF de etiquetas (spec 035): página del tamaño exacto del papel, cada etiqueta en su cuadro con el código de barras,
  # su número debajo y, según las casillas, el nombre y el precio. `check` entrega el resumen y los avisos sin armar el
  # archivo; `call` entrega los bytes del PDF.
  class PdfService
    MAX_LABELS = 1_000
    MAX_COPIES = 1_000
    PAD_X_MM = 1.5
    PAD_Y_MM = 1.0
    GAP_MM = 0.8
    NAME_SIZE = 6.5
    NUMBER_SIZE = 7.0
    PRICE_SIZE = 8.0
    # Altura mínima de las barras (mm) para que el código se lea; abajo de esto se avisa.
    MIN_BARS_MM = 6.0

    # Error de validación con el código de `details.code` que contesta la API.
    class Invalid < StandardError
      attr_reader :code, :details, :options

      def initialize(code, details = {}, **options)
        @code = code
        @details = details
        @options = options
        super(code.to_s)
      end
    end

    Label = Struct.new(:product, :code, :drawing, keyword_init: true)

    def initialize(company:, format:, items:, show_name: true, show_price: false, start_position: 1)
      @company = company
      @format = format
      @layout = Layout.new(format)
      @items = Array(items)
      @show_name = ActiveModel::Type::Boolean.new.cast(show_name)
      @show_price = ActiveModel::Type::Boolean.new.cast(show_price)
      @start_position = start_position.presence || 1
    end

    def check
      prepare
      { labels_count: @labels.size, pages: @layout.pages_for(@labels.size, start_position: @start), warnings: @warnings, skipped: @skipped }
    end

    def call
      prepare
      pdf = Prawn::Document.new(page_size: [ @layout.page_width, @layout.page_height ], margin: 0, info: { Title: "Etiquetas", Creator: "Draxuvo" })
      page = 0
      @labels.each_with_index do |label, index|
        slot = @layout.slot(index, start_position: @start)
        while page < slot.page
          pdf.start_new_page
          page += 1
        end
        draw_label(pdf, slot, label)
      end
      pdf.render
    end

    private

    def prepare
      return if @prepared

      validate_options
      products = @company.products.includes(:barcodes).where(id: @items.map { |item| item[:product_id].to_i }).index_by(&:id)
      @skipped = []
      @warnings = []
      @labels = []
      missing = []
      @items.each do |item|
        product = products[item[:product_id].to_i]
        next @skipped << { product_id: item[:product_id].to_i, reason: "not_found" } unless product

        code = chosen_code(product, item[:code])
        next missing << product unless code

        copies = Integer(item[:copies])
        drawing = drawing_for(product, code)
        next unless drawing

        warn_if_needed(product, drawing)
        @labels.concat(Array.new(copies) { Label.new(product: product, code: code, drawing: drawing) })
      end
      raise Invalid.new(:no_barcode, { products: missing.map { |p| { id: p.id, name: p.name } } }, products: missing.map(&:name).join(", ")) if missing.any?

      @prepared = true
    end

    def validate_options
      raise Invalid.new(:empty_items) if @items.empty?

      @items.each do |item|
        copies = Integer(item[:copies], exception: false)
        raise Invalid.new(:invalid_copies, {}, count: MAX_COPIES) unless copies&.between?(1, MAX_COPIES)
      end
      total = @items.sum { |item| Integer(item[:copies]) }
      raise Invalid.new(:too_many_labels, { max: MAX_LABELS }, count: MAX_LABELS) if total > MAX_LABELS

      @start = Integer(@start_position, exception: false)
      limit = @layout.roll? ? 1 : @layout.per_page
      raise Invalid.new(:invalid_start, {}, count: limit) unless @start&.between?(1, limit)
    end

    def chosen_code(product, requested)
      codes = product.barcode_codes
      return codes.first if requested.blank?
      raise Invalid.new(:invalid_code, { product_id: product.id }) unless codes.include?(requested.to_s.strip)

      requested.to_s.strip
    end

    def drawing_for(product, code)
      BarcodeDrawing.for(code)
    rescue BarcodeDrawing::Unsupported
      @skipped << { product_id: product.id, reason: "code_unsupported" }
      nil
    end

    # Avisos por producto (una sola vez, aunque tenga muchas copias): el código no cabe legible o falta espacio.
    def warn_if_needed(product, drawing)
      available_mm = @format.label_width_mm.to_f - (2 * PAD_X_MM)
      @warnings << warning(product, :code_too_small) unless drawing.readable_in?(available_mm)
      @warnings << warning(product, :content_too_big) if bars_height_mm(product) < MIN_BARS_MM
    end

    def warning(product, code)
      { product_id: product.id, code: code.to_s, message: I18n.t("labels.warnings.#{code}") }
    end

    def name_lines = @format.label_height_mm.to_f >= 30 ? 2 : 1

    def name_height_mm(product)
      @show_name && product.name.present? ? (name_lines * (NAME_SIZE * 0.3528 * 1.2)) + GAP_MM : 0
    end

    def number_height_mm = (NUMBER_SIZE * 0.3528 * 1.25)

    def bars_height_mm(product)
      @format.label_height_mm.to_f - (2 * PAD_Y_MM) - name_height_mm(product) - number_height_mm - GAP_MM
    end

    # --- dibujo ---

    def draw_label(pdf, slot, label)
      product = label.product
      pad_x = Layout.points(PAD_X_MM)
      pad_y = Layout.points(PAD_Y_MM)
      inner_x = slot.x + pad_x
      inner_w = slot.width - (2 * pad_x)
      cursor = slot.y + slot.height - pad_y

      if @show_name && product.name.present?
        height = Layout.points(name_height_mm(product) - GAP_MM)
        draw_name(pdf, product.name, inner_x, cursor, inner_w, height)
        cursor -= height + Layout.points(GAP_MM)
      end

      bars_h = Layout.points(bars_height_mm(product))
      label.drawing.draw(pdf, x: inner_x, y: cursor - bars_h, width: inner_w, height: bars_h)
      cursor -= bars_h + Layout.points(GAP_MM)
      draw_number_line(pdf, label, inner_x, cursor, inner_w)
    end

    def draw_name(pdf, name, x, top, width, height)
      pdf.font("Helvetica", style: :bold, size: NAME_SIZE) do
        lines = fit_lines(pdf, latin(name), width, name_lines)
        pdf.fill_color "000000"
        pdf.text_box lines.join("\n"), at: [ x, top ], width: width, height: height, align: :center, overflow: :truncate,
                                       leading: 0, single_line: false
      end
    end

    def draw_number_line(pdf, label, x, top, width)
      price = price_text(label.product)
      pdf.font("Helvetica", size: NUMBER_SIZE) do
        pdf.fill_color "000000"
        if price
          pdf.text_box label.code, at: [ x, top ], width: width, height: Layout.points(number_height_mm), align: :left, overflow: :shrink_to_fit
          pdf.font("Helvetica", style: :bold, size: PRICE_SIZE) do
            pdf.text_box price, at: [ x, top ], width: width, height: Layout.points(number_height_mm), align: :right
          end
        else
          pdf.text_box label.code, at: [ x, top ], width: width, height: Layout.points(number_height_mm), align: :center, overflow: :shrink_to_fit
        end
      end
    end

    def price_text(product)
      return unless @show_price && product.price

      "$#{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', product.price), delimiter: ',')}"
    end

    # Las fuentes incluidas en PDF solo traen Windows-1252 (acentos y ñ sí); lo demás sale como "?".
    def latin(text)
      text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    end

    # Parte `text` en hasta `max_lines` líneas que caben en `width`; si sobra texto la última termina en "…" (se usa "...").
    def fit_lines(pdf, text, width, max_lines)
      words = text.split
      lines = []
      current = ""
      words.each_with_index do |word, index|
        candidate = current.empty? ? word : "#{current} #{word}"
        if pdf.width_of(candidate) <= width
          current = candidate
        elsif lines.size + 1 < max_lines
          lines << current unless current.empty?
          current = word
        else
          current = ellipsize(pdf, words[index..].unshift(current).reject(&:empty?).join(" "), width)
          return lines << current
        end
      end
      lines << ellipsize(pdf, current, width)
    end

    def ellipsize(pdf, text, width)
      return text if pdf.width_of(text) <= width

      text = text[0...-1] while text.length > 1 && pdf.width_of("#{text}...") > width
      "#{text}..."
    end
  end
end
