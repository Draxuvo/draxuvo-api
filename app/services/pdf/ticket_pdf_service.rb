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

    def initialize(ticket)
      @ticket  = ticket
      @order   = ticket.work_order
      @check   = ticket.check
      @company = ticket.company
      @items   = @order ? @order.work_order_items.to_a : check_lines
    end

    def generate
      pdf = Prawn::Document.new(page_size: "A4", margin: [ 50, 50, 50, 50 ])
      draw_header(pdf)
      draw_info(pdf)
      draw_items(pdf) if @items.any?
      draw_totals(pdf)
      draw_payments(pdf)
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
        pdf.text "TICKET DE COBRO", size: 10
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
        if @order
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

    def payment_detail(payment)
      code = payment.respond_to?(:authorization_code) ? payment.authorization_code : nil
      [ payment.terminal&.name, payment.reference.presence || code ].compact_blank.join(" · ")
    end

    def draw_footer(pdf)
      pdf.stroke_color "DDDDDD"
      pdf.stroke_horizontal_rule
      pdf.move_down 6
      pdf.fill_color GRAY
      pdf.text "Generado el #{format_date(Time.current, with_time: true)}", size: 8, align: :center
      pdf.fill_color BLACK
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
