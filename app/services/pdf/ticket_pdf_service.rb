require "prawn"
require "prawn/table"

module Pdf
  class TicketPdfService
    PRIMARY   = "1E3A5F"
    LIGHT_BG  = "F7F9FC"
    GRAY      = "888888"
    BLACK     = "1A1A1A"
    WHITE     = "FFFFFF"
    GREEN     = "27AE60"

    Line = Struct.new(:description, :quantity, :unit, :unit_price, :subtotal)

    # Formatos del ticket de una venta de mostrador (spec 050): carta y rollo de impresora térmica de 58 u 80 mm.
    FORMATS = %w[a4 thermal58 thermal80].freeze
    THERMAL_WIDTH_MM = { "thermal58" => 58, "thermal80" => 80 }.freeze
    POINTS_PER_MM = 72 / 25.4
    THERMAL_MARGIN = 8
    THERMAL_PROBE_HEIGHT = 20_000
    # Código del folio (spec 056): Code 128 que la pistola y la cámara leen para abrir el ticket en Cobradas.
    A4_BARCODE_WIDTH = 220
    A4_BARCODE_HEIGHT = 40
    THERMAL_BARCODE_HEIGHT = 32

    def initialize(ticket, format: "a4")
      raise ArgumentError, "unknown ticket format: #{format.inspect}" unless FORMATS.include?(format.to_s)

      @ticket  = ticket
      @order   = ticket.work_order
      @check   = ticket.check
      @sale    = ticket.sale
      @company = ticket.company
      @format  = format.to_s
      @items   = @order ? @order.work_order_items.to_a : (@sale ? sale_lines : check_lines)
    end

    def generate
      return generate_thermal if THERMAL_WIDTH_MM.key?(@format)

      pdf = Prawn::Document.new(page_size: "A4", margin: [ 50, 50, 50, 50 ])
      draw_header(pdf)
      draw_cancelled(pdf) if cancelled_sale?
      draw_info(pdf)
      draw_items(pdf) if @items.any?
      draw_totals(pdf)
      draw_payments(pdf)
      draw_change(pdf) if @sale
      draw_folio_barcode(pdf, width: [ pdf.bounds.width, A4_BARCODE_WIDTH ].min, height: A4_BARCODE_HEIGHT, paginate: true)
      draw_footer(pdf)
      pdf.render
    end

    private

    def draw_header(pdf)
      pdf.fill_color PRIMARY
      pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 70
      pdf.fill_color WHITE
      pdf.bounding_box([ 15, pdf.cursor - 12 ], width: pdf.bounds.width - 30) do
        pdf.text @company.name.upcase, size: 18, style: :bold
        pdf.text(@sale ? I18n.t("sale.pdf.title") : "TICKET DE COBRO", size: 10)
      end
      pdf.fill_color BLACK
      pdf.move_down 85
    end

    def draw_info(pdf)
      col_w = (pdf.bounds.width - 10) / 2

      # Columna izquierda: datos del ticket
      pdf.bounding_box([ 0, pdf.cursor ], width: col_w) do
        label_value(pdf, "Folio",  @ticket.folio)
        label_value(pdf, "Fecha",  format_date(@ticket.created_at))
        label_value(pdf, "Estado", status_label)
        label_value(pdf, I18n.t("ticket.pdf.paid_at"), format_date(@ticket.paid_at)) if @ticket.paid_at
      end

      # Columna derecha: datos de la orden
      pdf.bounding_box([ col_w + 10, pdf.cursor + info_block_height(pdf) ], width: col_w) do
        if @sale
          label_value(pdf, I18n.t("sale.pdf.sale"), "##{@sale.id}")
          label_value(pdf, I18n.t("sale.pdf.cashier"), @ticket.charged_by&.full_name || "—")
        elsif @order
          label_value(pdf, "Orden",    @order.title)
          label_value(pdf, "Prioridad", priority_label)
          label_value(pdf, "Empleado", @order.employee&.name || "—")
        else
          label_value(pdf, "Cuenta", check_title)
          label_value(pdf, "Mesero", @check.waiter.full_name)
        end
      end

      pdf.move_down 20
      pdf.stroke_color "DDDDDD"
      pdf.stroke_horizontal_rule
      pdf.move_down 15
    end

    def draw_items(pdf)
      pdf.fill_color BLACK
      pdf.text "Detalle de servicios / productos", size: 11, style: :bold
      pdf.move_down 8

      header = [ [ "Descripción", "Cant.", "Unidad", "Precio unit.", "Subtotal" ] ]
      rows   = @items.map do |item|
        [
          item.description.to_s,
          item.quantity.to_s,
          item.unit.to_s,
          format_money(item.unit_price),
          format_money(item.subtotal)
        ]
      end

      pdf.table(header + rows, width: pdf.bounds.width, header: true) do
        row(0).background_color = PRIMARY
        row(0).text_color        = WHITE
        row(0).font_style        = :bold
        row(0).size              = 9

        columns(1..4).align = :right
        column(0).width     = 220

        self.row_colors = [ WHITE, LIGHT_BG ]
        self.cell_style = { padding: [ 6, 8 ], size: 9, border_width: 0 }
        self.header    = true
      end

      pdf.move_down 12
    end

    def draw_totals(pdf)
      box_w = 200
      x     = pdf.bounds.width - box_w

      pdf.fill_color LIGHT_BG
      pdf.fill_rectangle [ x, pdf.cursor ], box_w, 36
      pdf.fill_color BLACK

      pdf.bounding_box([ x + 10, pdf.cursor - 10 ], width: box_w - 20) do
        pdf.text "Total", size: 11, style: :bold
        pdf.move_up 14
        pdf.text format_money(@ticket.total), size: 14, style: :bold, align: :right
      end

      pdf.move_down 50
    end

    # Pagos de una cuenta o del cobro de una orden (spec 015): método, terminal y referencia o autorización, y
    # monto de cada uno. Los pagos anulados no salen.
    def draw_payments(pdf)
      payments = @check ? @check.check_payments.order(:id).to_a : @ticket.ticket_payments.active.to_a
      return if payments.empty?

      pdf.text "Pagos", size: 11, style: :bold
      pdf.move_down 6
      rows = payments.map do |payment|
        [ I18n.t("ticket.payment_method.#{payment.payment_method}"), payment_detail(payment), format_money(payment.amount) ]
      end
      pdf.table([ [ "Método", "Referencia", "Monto" ] ] + rows, width: pdf.bounds.width) do
        row(0).font_style = :bold
        columns(2).align = :right
        self.cell_style = { padding: [ 4, 8 ], size: 9, border_width: 0 }
      end
      pdf.move_down 12
    end

    # Venta de mostrador: lo recibido en efectivo y el cambio que se entregó.
    def draw_change(pdf)
      return unless @ticket.change_given.to_d.positive?

      pdf.text "#{I18n.t('sale.pdf.received')}: #{format_money(@ticket.amount_received)}", size: 9, align: :right
      pdf.text "#{I18n.t('sale.pdf.change')}: #{format_money(@ticket.change_given)}", size: 10, style: :bold, align: :right
      pdf.move_down 10
    end

    def draw_cancelled(pdf)
      pdf.fill_color "B42318"
      pdf.text I18n.t("sale.pdf.cancelled"), size: 16, style: :bold, align: :center
      pdf.text "#{I18n.t('sale.pdf.cancel_reason')}: #{safe(@sale.cancel_reason)}", size: 9, align: :center if @sale.cancel_reason.present?
      pdf.fill_color BLACK
      pdf.move_down 8
    end

    def payment_detail(payment)
      code = payment.respond_to?(:authorization_code) ? payment.authorization_code : nil
      [ payment.terminal&.name, payment.reference.presence || code ].compact_blank.join(" · ")
    end

    # Code 128 con el folio y el folio escrito debajo. Si el folio no se pudiera dibujar el ticket sale sin código en vez
    # de fallar. `paginate` (A4) pasa a otra página si no cabe; el rollo térmico mide su altura con una pasada de prueba.
    def draw_folio_barcode(pdf, width:, height:, paginate: false)
      drawing = Labels::BarcodeDrawing.for(@ticket.folio)
      pdf.start_new_page if paginate && pdf.cursor < height + 30
      x = (pdf.bounds.width - width) / 2.0
      drawing.draw(pdf, x: x, y: pdf.cursor - height, width: width, height: height)
      pdf.move_down height + 2
      pdf.fill_color BLACK
      pdf.text drawing.human_text, size: 7, align: :center
      pdf.move_down 6
    rescue Labels::BarcodeDrawing::Unsupported
      nil
    end

    def draw_footer(pdf)
      pdf.stroke_color "DDDDDD"
      pdf.stroke_horizontal_rule
      pdf.move_down 6
      pdf.fill_color GRAY
      pdf.text "Generado el #{format_date(Time.current, with_time: true)}", size: 8, align: :center
      pdf.fill_color BLACK
    end

    # --- Rollo térmico (spec 050): una sola columna; la altura se mide con una pasada de prueba para que no sobre papel ---

    def generate_thermal
      width = THERMAL_WIDTH_MM.fetch(@format) * POINTS_PER_MM
      probe = Prawn::Document.new(page_size: [ width, THERMAL_PROBE_HEIGHT ], margin: THERMAL_MARGIN)
      draw_thermal(probe)
      used = THERMAL_PROBE_HEIGHT - probe.y + THERMAL_MARGIN * 2
      pdf = Prawn::Document.new(page_size: [ width, [ used, 120 ].max ], margin: THERMAL_MARGIN)
      draw_thermal(pdf)
      pdf.render
    end

    def draw_thermal(pdf)
      pdf.text safe(@company.name.upcase), size: 11, style: :bold, align: :center
      pdf.text(@sale ? I18n.t("sale.pdf.title") : "TICKET", size: 8, align: :center)
      pdf.move_down 4
      thermal_line(pdf, "Folio", @ticket.folio)
      thermal_line(pdf, "Fecha", format_date(@ticket.paid_at || @ticket.created_at, with_time: true))
      thermal_line(pdf, I18n.t("sale.pdf.cashier"), @ticket.charged_by&.full_name) if @sale
      draw_thermal_cancelled(pdf) if cancelled_sale?
      thermal_rule(pdf)
      @items.each { |item| draw_thermal_item(pdf, item) }
      thermal_rule(pdf)
      pdf.text "Total  #{format_money(@ticket.total)}", size: 12, style: :bold, align: :right
      draw_thermal_payments(pdf)
      pdf.move_down 6
      draw_folio_barcode(pdf, width: pdf.bounds.width, height: THERMAL_BARCODE_HEIGHT)
      pdf.text I18n.t("sale.pdf.thanks"), size: 7, align: :center
    end

    def draw_thermal_item(pdf, item)
      pdf.text safe(item.description), size: 8
      pdf.text "#{item.quantity} x #{format_money(item.unit_price)}   #{format_money(item.subtotal)}", size: 8, align: :right
      pdf.move_down 2
    end

    def draw_thermal_payments(pdf)
      payments = @ticket.ticket_payments.active.to_a
      payments.each do |payment|
        pdf.text "#{I18n.t("ticket.payment_method.#{payment.payment_method}")}  #{format_money(payment.amount)}", size: 8, align: :right
      end
      return unless @ticket.change_given.to_d.positive?

      pdf.text "#{I18n.t('sale.pdf.received')}  #{format_money(@ticket.amount_received)}", size: 8, align: :right
      pdf.text "#{I18n.t('sale.pdf.change')}  #{format_money(@ticket.change_given)}", size: 9, style: :bold, align: :right
    end

    def draw_thermal_cancelled(pdf)
      pdf.move_down 4
      pdf.text I18n.t("sale.pdf.cancelled"), size: 12, style: :bold, align: :center
      pdf.text safe(@sale.cancel_reason), size: 7, align: :center if @sale.cancel_reason.present?
    end

    def thermal_line(pdf, label, value)
      pdf.text "#{label}: #{safe(value)}", size: 8
    end

    def thermal_rule(pdf)
      pdf.move_down 3
      pdf.stroke_color "999999"
      pdf.dash(2, space: 2)
      pdf.stroke_horizontal_rule
      pdf.undash
      pdf.move_down 4
    end

    # Helpers

    def label_value(pdf, label, value)
      pdf.fill_color GRAY
      pdf.text label, size: 8
      pdf.fill_color BLACK
      pdf.text value.to_s, size: 10, style: :bold
      pdf.move_down 4
    end

    def info_block_height(_pdf)
      # Aproximación de altura del bloque de info izquierdo
      90
    end

    def format_date(dt, with_time: false)
      return "—" if dt.nil?
      with_time ? dt.strftime("%d/%m/%Y %H:%M") : dt.strftime("%d/%m/%Y")
    end

    def format_money(amount)
      return "—" if amount.nil?
      "$#{format('%.2f', amount)}"
    end

    def status_label
      I18n.t("ticket.status.#{@ticket.status}")
    end

    def sale_lines
      @sale.sale_items.map { |item| Line.new(safe(item.name), Product.quantity(item.quantity), nil, item.unit_price, item.subtotal) }
    end

    def cancelled_sale? = @sale&.status_cancelled?

    # Las fuentes estándar de PDF solo cubren Windows-1252: lo que no cabe (emojis) se cambia por "?" en vez de romper el PDF.
    def safe(text)
      text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    end

    def check_lines
      @check.check_items.counted.order(:id).map do |item|
        Line.new(item.name, item.quantity, nil, item.unit_price, item.subtotal)
      end
    end

    def check_title
      @check.dining_table ? "Mesa #{@check.dining_table.name}" : "Para llevar: #{@check.takeout_name}"
    end

    def priority_label
      I18n.t("work_order.priority.#{@order.priority}")
    end
  end
end
