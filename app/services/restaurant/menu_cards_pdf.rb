require "prawn"
require "rqrcode_core"

module Restaurant
  # Tarjetas QR de las mesas (spec 059): hoja carta partida en 2 × 2 (≈ 10.8 × 14 cm por tarjeta) con líneas de corte.
  # Cada tarjeta lleva el nombre del negocio, el QR con el enlace de la mesa, el nombre de la mesa y el texto de ayuda,
  # sin marca Draxuvo (FR-026). Recibe mesas que ya tienen token: el controlador lo asegura y valida la lista.
  # Spec 065: con logo de la empresa (spec 063) se dibuja arriba y el nombre va debajo, más chico; para que quepa sin
  # achicar el QR se acortan las separaciones. Sin logo, o si no se puede leer, la tarjeta queda como antes.
  class MenuCardsPdf
    MM = 72 / 25.4
    PAGE_WIDTH = 612.0  # carta
    PAGE_HEIGHT = 792.0
    COLUMNS = 2
    ROWS = 2
    PER_PAGE = COLUMNS * ROWS
    CARD_WIDTH = PAGE_WIDTH / COLUMNS
    CARD_HEIGHT = PAGE_HEIGHT / ROWS
    # Las impresoras de oficina no imprimen los 4–5 mm de la orilla; el contenido queda dentro de 10 mm.
    PADDING = 10 * MM
    QR_SIZE = 65 * MM
    QUIET_ZONE = 4 # módulos en blanco alrededor del QR, los que pide el estándar
    BUSINESS_SIZE = 18
    TABLE_SIZE = 30
    HINT_SIZE = 11
    BUSINESS_HEIGHT = 44
    QR_GAP = 5 * MM
    NAME_GAP = 4 * MM
    NAME_HEIGHT = TABLE_SIZE + 6
    HINT_GAP = 4
    HINT_HEIGHT = HINT_SIZE + 6
    # Con logo: franja del logo, nombre más chico debajo y separaciones de 3 mm alrededor del QR (research R1).
    LOGO_HEIGHT = 19 * MM
    LOGO_GAP = 3
    LOGO_BUSINESS_SIZE = 12
    LOGO_BUSINESS_HEIGHT = 20
    LOGO_QR_GAP = 3 * MM
    LOGO_NAME_GAP = 3 * MM

    Layout = Struct.new(:logo, :business_height, :business_size, :qr_gap, :name_gap, keyword_init: true) do
      def header_height = (logo ? LOGO_HEIGHT + LOGO_GAP : 0) + business_height

      def content_height = header_height + qr_gap + QR_SIZE + name_gap + NAME_HEIGHT + HINT_GAP + HINT_HEIGHT
    end

    PLAIN = Layout.new(logo: false, business_height: BUSINESS_HEIGHT, business_size: BUSINESS_SIZE, qr_gap: QR_GAP, name_gap: NAME_GAP).freeze
    WITH_LOGO = Layout.new(logo: true, business_height: LOGO_BUSINESS_HEIGHT, business_size: LOGO_BUSINESS_SIZE,
                           qr_gap: LOGO_QR_GAP, name_gap: LOGO_NAME_GAP).freeze

    def self.content_height(logo:) = (logo ? WITH_LOGO : PLAIN).content_height

    def initialize(company:, tables:)
      @company = company
      @tables = Array(tables)
      missing = @tables.reject { |table| table.menu_token.present? }
      raise ArgumentError, "mesas sin enlace: #{missing.map(&:id).join(', ')}" if missing.any?
    end

    def call
      @logo = read_logo
      @layout = @logo ? WITH_LOGO : PLAIN
      pdf = Prawn::Document.new(page_size: [ PAGE_WIDTH, PAGE_HEIGHT ], margin: 0,
                                info: { Title: I18n.t("restaurant.menu_cards.title") })
      @tables.each_slice(PER_PAGE).with_index do |page_tables, page|
        pdf.start_new_page if page.positive?
        draw_cut_lines(pdf)
        page_tables.each_with_index { |table, slot| draw_card(pdf, table, slot) }
      end
      pdf.render
    end

    private

    def draw_cut_lines(pdf)
      pdf.save_graphics_state do
        pdf.stroke_color "AAAAAA"
        pdf.line_width 0.5
        pdf.dash(4, space: 4)
        pdf.stroke_line [ CARD_WIDTH, 0 ], [ CARD_WIDTH, PAGE_HEIGHT ]
        pdf.stroke_line [ 0, CARD_HEIGHT ], [ PAGE_WIDTH, CARD_HEIGHT ]
        pdf.undash
      end
    end

    # `slot` 0..3: de izquierda a derecha y de arriba abajo. Prawn mide desde la esquina inferior izquierda.
    def draw_card(pdf, table, slot)
      left = (slot % COLUMNS) * CARD_WIDTH + PADDING
      width = CARD_WIDTH - (2 * PADDING)
      # El bloque va centrado en vertical dentro del área imprimible de la tarjeta.
      inner_height = CARD_HEIGHT - (2 * PADDING)
      layout = @layout
      top = PAGE_HEIGHT - (slot / COLUMNS) * CARD_HEIGHT - PADDING - ((inner_height - layout.content_height) / 2)

      business_top = top
      if layout.logo
        draw_logo(pdf, left, top, width)
        business_top = top - LOGO_HEIGHT - LOGO_GAP
      end

      pdf.fill_color "141414"
      pdf.font("Helvetica", style: :bold) do
        pdf.text_box latin(@company.name), at: [ left, business_top ], width: width, height: layout.business_height,
                     size: layout.business_size,
                     align: :center, valign: :center, overflow: :shrink_to_fit, min_font_size: 8, disable_wrap_by_char: true
      end

      qr_top = top - layout.header_height - layout.qr_gap
      draw_qr(pdf, table.menu_url, left + ((width - QR_SIZE) / 2), qr_top)

      name_top = qr_top - QR_SIZE - layout.name_gap
      pdf.font("Helvetica", style: :bold) do
        pdf.text_box latin(self.class.table_label(table.name)), at: [ left, name_top ], width: width, height: NAME_HEIGHT,
                     size: TABLE_SIZE,
                     align: :center, valign: :center, overflow: :shrink_to_fit, min_font_size: 10, disable_wrap_by_char: true
      end

      pdf.fill_color "4A4F55"
      pdf.font("Helvetica") do
        pdf.text_box latin(I18n.t("restaurant.menu_cards.scan_hint")), at: [ left, name_top - NAME_HEIGHT - HINT_GAP ],
                     width: width, height: HINT_HEIGHT, size: HINT_SIZE, align: :center, overflow: :shrink_to_fit
      end
      pdf.fill_color "000000"
    end

    # El logo (versión para imprimir de la spec 063) centrado en su franja, sin deformarse ni recortarse.
    def draw_logo(pdf, left, top, width)
      pdf.bounding_box([ left, top ], width: width, height: LOGO_HEIGHT) do
        pdf.image StringIO.new(@logo), fit: [ width, LOGO_HEIGHT ], position: :center, vposition: :center
      end
    end

    # Se lee una vez por PDF. Si no se puede (almacenamiento caído, versión sin preparar), las tarjetas salen sin logo.
    def read_logo
      @company.logo_print_io&.read
    rescue StandardError => e
      Rails.logger.warn("[MenuCardsPdf] company=#{@company.id} logo skipped: #{e.class}: #{e.message}")
      nil
    end

    # Cada módulo oscuro es un cuadro (vectorial, nítido en cualquier impresora); los oscuros seguidos de una fila se
    # juntan en un rectángulo y todos se rellenan en una sola operación, para que el visor no deje rayas blancas entre
    # filas vecinas por el suavizado.
    def draw_qr(pdf, url, left, top)
      qr = RQRCodeCore::QRCode.new(url, level: :m)
      count = qr.module_count
      size = QR_SIZE / (count + (2 * QUIET_ZONE))
      pdf.fill_color "000000"
      count.times do |row|
        col = 0
        while col < count
          unless qr.checked?(row, col)
            col += 1
            next
          end

          start = col
          col += 1 while col < count && qr.checked?(row, col)
          x = left + ((start + QUIET_ZONE) * size)
          y = top - ((row + QUIET_ZONE) * size)
          pdf.rectangle [ x, y ], (col - start) * size, size
        end
      end
      pdf.fill
    end

    # Una mesa que se llama solo con un número sale como «Mesa 4»; cualquier otro nombre, tal cual (igual que la página).
    def self.table_label(name)
      name.to_s.strip.match?(/\A\d+\z/) ? I18n.t("restaurant.menu_cards.table", name: name.to_s.strip) : name.to_s
    end

    # Las fuentes incluidas en PDF solo traen Windows-1252 (acentos y ñ sí); lo demás sale como "?" (como las etiquetas).
    def latin(text)
      text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    end
  end
end
