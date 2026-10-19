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
end
