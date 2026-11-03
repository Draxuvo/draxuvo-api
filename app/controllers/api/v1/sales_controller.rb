# Venta de mostrador (spec 050, contracts/api.md). Exige el módulo `pos`. El staff solo ve y opera las ventas que
# abrió; dueño y administrador ven todas. Las reglas finas viven en Sales::Permissions.
module Api
  module V1
    class SalesController < BaseController
      include Idempotent

      requires_module :pos
      requires_module :whatsapp, only: :ticket_whatsapp
      idempotent :charge

      before_action :set_sale, except: %i[index create catalog]

      # GET /api/v1/sales
      def index
        sales = filtered_sales.includes(:opened_by, :charged_by, :sale_items, :ticket)
        sales = params[:status].blank? ? sales.reorder(Arel.sql("CASE WHEN sales.status = 0 THEN 0 ELSE 1 END"), created_at: :desc) : sales.reorder(created_at: :desc)
        @pagy, sales = pagy(sales)
        render json: paginate_response(@pagy, sales.map { |sale| SaleSerializer.new(sale, context: context, detailed: false).as_json })
      end

      # GET /api/v1/sales/catalog — productos que la caja puede agregar.
      def catalog
        products = current_company.products.available.sellable.where.not(price: nil).includes(:product_type, :barcodes).search(params[:search])
        products = exact_match_first(products)
        @pagy, products = pagy(products)
        render json: paginate_response(@pagy, products.map { |product| catalog_json(product) })
      end

      # POST /api/v1/sales
      def create
        sale = current_company.sales.create!(opened_by: current_user)
        render json: serialize(sale), status: :created
      end

      def show
        render json: serialize(@sale)
      end

      # POST /api/v1/sales/:id/items
      def add_item
        render json: serialize(Sales::AddItem.call(@sale, item_params))
      end

      # PATCH /api/v1/sales/:id/items/:item_id
      def update_item
        render json: serialize(Sales::UpdateItem.call(@sale, params[:item_id], params[:quantity]))
      end

      # DELETE /api/v1/sales/:id/items/:item_id
      def remove_item
        render json: serialize(Sales::RemoveItem.call(@sale, params[:item_id]))
      end

      # DELETE /api/v1/sales/:id — descarta una venta abierta.
      def destroy
        raise_sale_not_open! unless @sale.status_open?

        @sale.destroy!
        head :no_content
      end

      # POST /api/v1/sales/:id/charge
      def charge
        result = Sales::Charge.call(@sale, current_user, params)
        render json: { sale: serialize(result.sale.reload), shortages: result.shortages }
      end

      # POST /api/v1/sales/:id/cancel — { reason }. Solo dueño y administrador.
      def cancel
        forbid! unless Sales::Permissions.cancel?(@sale, context)

        render json: serialize(Sales::Cancel.call(@sale, current_user, params[:reason]).reload)
      end

      # GET /api/v1/sales/:id/ticket — el ticket de una venta cobrada o cancelada.
      def ticket
        render json: TicketSerializer.new(ticket_of(@sale), detailed: true).as_json.merge(company: { name: current_company.name })
      end

      # GET /api/v1/sales/:id/ticket.pdf?paper=a4|thermal58|thermal80 (no `format`: Rails lo toma como el formato de la respuesta)
      def ticket_pdf
        format = params[:paper].presence || "a4"
        unless Pdf::TicketPdfService::FORMATS.include?(format)
          raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("sale.errors.invalid_format"), details: { code: "invalid_format" })
        end

        ticket = ticket_of(@sale)
        send_data Pdf::TicketPdfService.new(ticket, format: format).generate,
                  filename: "ticket-#{ticket.folio}-#{format}.pdf", type: "application/pdf", disposition: "attachment"
      end

      # POST /api/v1/sales/:id/ticket/whatsapp — { phone }
      def ticket_whatsapp
        ticket = ticket_of(@sale)
        phone = params[:phone].to_s.strip
        raise ApiErrors::BadRequestError.new(details: I18n.t("ticket.phone_required")) if phone.empty?

        ::Whatsapp::TicketService.new(ticket, phone: phone).call
        body = { message: I18n.t("ticket.whatsapp_sent") }
        body[:demo] = true if Demo::Guard.active?
        render json: body
      end

      private

      # El ticket existe solo con la venta cobrada (o cancelada después de cobrar).
      def ticket_of(sale)
        sale.ticket || raise(ApiErrors::UnprocessableEntityError.new(message: I18n.t("sale.errors.not_paid"), details: { code: "sale_not_paid" }))
      end

      def context
        @context ||= Sales::Permissions::Context.new(user: current_user, role: current_role)
      end

      def base_scope
        scope = current_company.sales
        context.boss? ? scope : scope.where(opened_by_id: current_user.id)
      end

      def set_sale
        @sale = base_scope.includes(:sale_items, :ticket).find(params[:id])
      end

      # `whatsapp_available` dice si la empresa puede mandar el ticket por WhatsApp (el staff no lee la suscripción).
      def serialize(sale)
        SaleSerializer.new(sale, context: context).as_json.merge(whatsapp_available: current_company.module_active?(:whatsapp))
      end

      def item_params
        params.permit(:product_id, :barcode, :sku, :quantity)
      end

      def filtered_sales
        sales = base_scope
        sales = sales.where(status: params[:status]) if Sale.statuses.key?(params[:status])
        sales = sales.where(created_at: date(params[:from]).beginning_of_day..) if date(params[:from])
        sales = sales.where(created_at: ..date(params[:to]).end_of_day) if date(params[:to])
        sales = sales.where(opened_by_id: params[:opened_by_id]) if params[:opened_by_id].present? && context.boss?
        params[:search].present? ? search(sales, params[:search]) : sales
      end

      def search(sales, query)
        term = "%#{Sale.sanitize_sql_like(query.to_s.strip)}%"
        sales.where(
          "EXISTS (SELECT 1 FROM tickets t WHERE t.sale_id = sales.id AND t.folio ILIKE :term) OR " \
          "EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id = sales.id AND si.name ILIKE :term)", term: term
        )
      end

      def date(value)
        Date.iso8601(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end

      # La coincidencia exacta de SKU o código de barras va primero, como en Inventario.
      def exact_match_first(products)
        return products.order(:name) if params[:search].blank?

        code = ActiveRecord::Base.connection.quote(params[:search].to_s.strip)
        products.order(
          Arel.sql("CASE WHEN products.sku = #{code} OR EXISTS (SELECT 1 FROM product_barcodes pb WHERE pb.product_id = products.id AND pb.code = #{code}) THEN 0 ELSE 1 END"),
          :name
        )
      end

      def catalog_json(product)
        type = product.product_type
        {
          id: product.id, name: product.name, sku: product.sku, price: format("%.2f", product.price),
          icon: product.icon || type&.icon, category: product.category,
          stock: type&.counted ? Product.quantity(product.stock) : nil, fractional: !!type&.fractional,
          barcodes: product.barcode_codes
        }
      end

      def raise_sale_not_open!
        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("sale.errors.not_open"), details: { code: "not_open" })
      end
    end
  end
end
