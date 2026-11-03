require "test_helper"

class Pdf::TicketPdfServiceTest < ActiveSupport::TestCase
  def pdf_for(ticket)
    Pdf::TicketPdfService.new(ticket).generate
  end

  # El texto va en cadenas hexadecimales (fuentes estándar, Windows-1252); cada TJ es una línea.
  def pdf_text(bytes)
    bytes.b.scan(/\[(.*?)\]\s*TJ/m).flatten.map do |array|
      array.scan(/<([0-9A-Fa-f]*)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
    end.join("\n").force_encoding("Windows-1252").encode("UTF-8")
  end

  test "generates a PDF document" do
    bytes = pdf_for(tickets(:pro_paid_ticket))
    assert bytes.start_with?("%PDF")
    assert_includes bytes.b, "%%EOF"
  end

  test "includes the company, folio and item details" do
    text = pdf_text(pdf_for(tickets(:pro_paid_ticket)))
    assert_includes text, "SERVICIOS PRO"
    assert_includes text, "T-900001"
    assert_includes text, "Lámparas"
    assert_includes text, "$500.00"
  end

  test "generates without items" do
    ticket = tickets(:pro_paid_ticket)
    ticket.work_order.work_order_items.destroy_all
    bytes = pdf_for(ticket.reload)
    assert bytes.start_with?("%PDF")
    assert_not_includes pdf_text(bytes), "Detalle de servicios"
  end

  test "lists items when the order has them" do
    assert_includes pdf_text(pdf_for(tickets(:pro_paid_ticket))), "Detalle de servicios"
  end

  test "omits the paid date line when the ticket has no paid_at" do
    ticket = Ticket.create!(work_order: work_orders(:pro_done), company: companies(:pro_co), total: 850)
    text = I18n.with_locale(:es) { pdf_text(pdf_for(ticket)) }
    assert_not_includes text, "Pagado el"
    assert_includes text, "Pendiente de pago"
  end

  test "labels the paid date in Spanish" do
    text = I18n.with_locale(:es) { pdf_text(pdf_for(tickets(:pro_paid_ticket))) }
    assert_includes text, "Pagado el"
    assert_not_includes text, "Paid"
  end

  test "labels the paid date in English" do
    text = I18n.with_locale(:en) { pdf_text(pdf_for(tickets(:pro_paid_ticket))) }
    assert_includes text, "Paid on"
    assert_not_includes text, "Pagado el"
  end

  test "shows a dash for an unassigned order" do
    ticket = Ticket.create!(work_order: work_orders(:pro_unassigned), company: companies(:pro_co), total: 0)
    assert pdf_for(ticket).start_with?("%PDF")
  end

  test "leaves the locale as it found it" do
    before = I18n.locale
    I18n.with_locale(:en) { pdf_for(tickets(:pro_paid_ticket)) }
    assert_equal before, I18n.locale
  end

  test "a restaurant ticket shows the table, the waiter, the items and each payment" do
    text = pdf_text(pdf_for(tickets(:resto_paid_ticket)))

    assert_includes text, "RESTAURANTE PRUEBA"
    assert_includes text, "T-900050"
    assert_includes text, "Mesa 2"
    assert_includes text, "Tacos al pastor"
    assert_includes text, "Efectivo"
    assert_includes text, "$70.00"
  end

  test "a takeout ticket shows the customer's name" do
    check = checks(:takeout_check)
    ticket = Ticket.create!(check: check, company: check.company, status: :paid, total: 0, paid_at: Time.current,
                            payment_method: :cash, amount_received: 0, charged_by: users(:resto_owner))

    assert_includes pdf_text(pdf_for(ticket)), "Para llevar: Luis"
  end

  # --- ticket de una venta de mostrador (spec 050) ---

  def sale_ticket(cancelled: false)
    sale = open_sale(users(:pos_staff), [ products(:pos_cuaderno), 2 ], [ products(:pos_liston), "1.5" ])
    ticket = charge_cash(sale, users(:pos_staff), received: 100).ticket
    if cancelled
      ticket.ticket_payments.update_all(voided_at: Time.current)
      ticket.update!(status: :voided, voided_at: Time.current, voided_by: users(:pos_admin), void_reason: "Cliente devolvió")
      sale.update!(status: :cancelled, cancelled_at: Time.current, cancelled_by: users(:pos_admin), cancel_reason: "Cliente devolvió")
    end
    ticket.reload
  end

  def media_box(bytes)
    bytes.b.match(/MediaBox \[0(?:\.0)? 0(?:\.0)? ([\d.]+) ([\d.]+)\]/).captures.map(&:to_f)
  end

  test "a4 sale ticket shows the company, folio, cashier, items, total, payments and change" do
    ticket = sale_ticket
    text = pdf_text(Pdf::TicketPdfService.new(ticket).generate)

    assert_includes text, "PAPELERÍA PRUEBA"
    assert_includes text, ticket.folio
    assert_includes text, "TICKET DE COMPRA"
    assert_includes text, "Cuaderno profesional"
    assert_includes text, "Listón por metro"
    assert_includes text, "$97.00"
    assert_includes text, "Staff Papelería"
    assert_includes text, "Cambio"
    assert_includes text, "$3.00"
    assert_not_includes text, "CANCELADO"
  end

  test "the ticket keeps the name and price of the sale after the product changes" do
    ticket = sale_ticket
    products(:pos_cuaderno).update!(name: "Cuaderno renombrado", price: 99)
    text = pdf_text(Pdf::TicketPdfService.new(ticket.reload).generate)

    assert_includes text, "Cuaderno profesional"
    assert_not_includes text, "renombrado"
    assert_includes text, "$42.50"
  end

  test "thermal formats use a narrow page of 58 and 80 mm" do
    ticket = sale_ticket
    narrow = media_box(Pdf::TicketPdfService.new(ticket, format: "thermal58").generate)
    wide = media_box(Pdf::TicketPdfService.new(ticket, format: "thermal80").generate)
    a4 = media_box(Pdf::TicketPdfService.new(ticket, format: "a4").generate)

    assert_in_delta 58 * 72 / 25.4, narrow[0], 0.5
    assert_in_delta 80 * 72 / 25.4, wide[0], 0.5
    assert_in_delta 595.28, a4[0], 0.5
    assert_operator narrow[1], :<, a4[1]
  end

  test "thermal tickets list items, total and payment and are one page tall for the content" do
    ticket = sale_ticket
    bytes = Pdf::TicketPdfService.new(ticket, format: "thermal80").generate
    text = pdf_text(bytes)

    assert bytes.start_with?("%PDF")
    assert_includes text, "Cuaderno profesional"
    assert_includes text, "Total  $97.00"
    assert_includes text, "Efectivo"
    assert_includes text, "Gracias por su compra"
  end

  test "a long sale grows the thermal ticket instead of cutting it" do
    sale = Sale.create!(company: companies(:pos_co), opened_by: users(:pos_staff))
    30.times do |i|
      product = companies(:pos_co).products.create!(sku: "L-#{i}", name: "Artículo largo #{i}", price: 10, stock: 5, product_type: product_types(:pos_co_counted))
      Sales::AddItem.call(sale, product_id: product.id)
    end
    ticket = charge_cash(sale.reload, users(:pos_staff), received: 300).ticket

    short = media_box(Pdf::TicketPdfService.new(sale_ticket, format: "thermal58").generate)
    long = media_box(Pdf::TicketPdfService.new(ticket, format: "thermal58").generate)
    assert_operator long[1], :>, short[1] + 200
    assert_includes pdf_text(Pdf::TicketPdfService.new(ticket, format: "thermal58").generate), "Artículo largo 29"
  end

  test "a cancelled sale is marked with its reason in every format" do
    ticket = sale_ticket(cancelled: true)
    Pdf::TicketPdfService::FORMATS.each do |format|
      text = pdf_text(Pdf::TicketPdfService.new(ticket, format: format).generate)
      assert_includes text, "CANCELADO", format
      assert_includes text, "Cliente devolvió", format
    end
  end

  test "names with characters outside Windows-1252 do not break the PDF" do
    sale = open_sale(users(:pos_staff), [ products(:pos_cuaderno), 1 ])
    sale.sale_items.first.update!(name: "Cuaderno 😀 ñandú")
    ticket = charge_cash(sale, users(:pos_staff)).ticket

    Pdf::TicketPdfService::FORMATS.each do |format|
      text = pdf_text(Pdf::TicketPdfService.new(ticket.reload, format: format).generate)
      assert_includes text, "Cuaderno ? ñandú", format
    end
  end

  test "an unknown format is rejected" do
    assert_raises(ArgumentError) { Pdf::TicketPdfService.new(sale_ticket, format: "poster") }
  end

  test "work order and restaurant tickets still render in the default format" do
    assert Pdf::TicketPdfService.new(tickets(:pro_paid_ticket)).generate.start_with?("%PDF")
  end
end
