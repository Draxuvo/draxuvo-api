# Una venta de mostrador para la API (spec 050, contracts/api.md). Con el ticket y sus pagos cuando ya se cobró.
class SaleSerializer
  def initialize(sale, context: nil, detailed: true)
    @sale = sale
    @context = context
    @detailed = detailed
  end

  def as_json(*)
    base = {
      id: @sale.id,
      status: @sale.status,
      status_label: I18n.t("sale.status.#{@sale.status}"),
      total: money(@sale.total),
      items_count: @sale.sale_items.size,
      opened_by: TicketSerializer.person(@sale.opened_by),
      charged_by: TicketSerializer.person(@sale.charged_by),
      paid_at: @sale.paid_at,
      cancelled_at: @sale.cancelled_at,
      cancelled_by: TicketSerializer.person(@sale.cancelled_by),
      cancel_reason: @sale.cancel_reason,
      lock_version: @sale.lock_version,
      created_at: @sale.created_at,
      folio: @sale.ticket&.folio
    }
    base[:actions] = Sales::Permissions.actions(@sale, @context) if @context
    return base unless @detailed

    base.merge(items: @sale.sale_items.map { |item| item_json(item) }, ticket: ticket_json)
  end

  # Renglón con el icono y la existencia actual del producto (si todavía existe).
  def item_json(item)
    product = item.product
    {
      id: item.id, product_id: item.product_id, name: item.name, sku: item.sku,
      unit_price: money(item.unit_price), quantity: Product.quantity(item.quantity), subtotal: money(item.subtotal),
      icon: product&.icon || product&.product_type&.icon,
      stock: product&.counted? ? Product.quantity(product.stock) : nil,
      fractional: product ? !!product.fractional? : false
    }
  end

  private

  def ticket_json
    ticket = @sale.ticket
    ticket && TicketSerializer.person_ticket(ticket)
  end

  def money(value) = value.nil? ? nil : format("%.2f", value)
end
