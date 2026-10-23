module Api
  module V1
    # Conteo físico en borrador (spec 034): se escanea, se ve la diferencia contra el stock y se confirma.
    class StockCountsController < BaseController
      requires_module :inventory
      before_action :set_count, except: %i[index create]
      before_action :require_draft!, only: %i[scan update_item destroy_item]

      def index
        counts = current_company.stock_counts.includes(:user, :items).recent
        counts = counts.where(status: params[:status]) if StockCount.statuses.key?(params[:status])
        @pagy, @counts = pagy(counts)
        render json: paginate_response(@pagy, @counts.map { |count| StockCountSerializer.new(count, items: false).as_json })
      end

      def create
        count = current_company.stock_counts.create!(user: current_user, name: params[:name].presence)
        render json: serialize(count), status: :created
      end

      def show
        render json: serialize(@count)
      end

      # Suma `qty` (1 por defecto) a lo contado del producto del código; dos escaneos simultáneos suman sin pisarse.
      def scan
        product = scanned_product
        qty = parse_qty(params[:qty] || 1)
        guard_product!(product, qty)
        increment!(product, qty)
        render json: serialize(@count)
      end

      def update_item
        item = @count.items.find_by!(product_id: params[:product_id])
        item.update!(counted_qty: parse_qty(params[:counted_qty], allow_zero: true))
        render json: serialize(@count)
      end

      def destroy_item
        @count.items.find_by!(product_id: params[:product_id]).destroy!
        render json: serialize(@count)
      end

      def confirm
        result = Stock::ConfirmCount.call(count: @count, user: current_user)
        render json: { count: serialize(result.count),
                       adjustments: result.adjustments.map { |m| StockMovementSerializer.new(m).as_json },
                       changed_since_baseline: result.changed_since_baseline }
      rescue Stock::ConfirmCount::Invalid => e
        invalid!(e.code, e.product)
      end

      def destroy
        invalid!(:count_closed) if @count.confirmed?
        @count.discarded! unless @count.discarded?
        head :no_content
      end

      private

      def set_count
        @count = current_company.stock_counts.find(params[:id])
      end

      def require_draft!
        invalid!(:count_closed) unless @count.draft?
      end

      def serialize(count)
        fresh = current_company.stock_counts.includes(:user, items: { product: %i[product_type barcodes] }).find(count.id)
        StockCountSerializer.new(fresh).as_json
      end

      def scanned_product
        if params[:product_id].present?
          current_company.products.find(params[:product_id])
        else
          Products::Lookup.call(current_company, params[:code]) ||
            raise(ApiErrors::NotFoundError.new(message: I18n.t("stock.errors.code_not_found"), details: { code: "code_not_found" }))
        end
      end

      def parse_qty(value, allow_zero: false)
        qty = BigDecimal(value.to_s)
        invalid!(:invalid_qty) if qty.negative? || (!allow_zero && qty.zero?)
        qty
      rescue ArgumentError
        invalid!(:invalid_qty)
      end

      def guard_product!(product, qty)
        invalid!(:not_counted, product) unless product.counted?
        invalid!(:invalid_qty) if !product.fractional? && qty != qty.round
      end

      def increment!(product, qty)
        now = Time.current
        StockCountItem.connection.execute(StockCountItem.sanitize_sql_array([
          "INSERT INTO stock_count_items (stock_count_id, product_id, counted_qty, baseline_stock, created_at, updated_at) " \
          "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (stock_count_id, product_id) DO UPDATE " \
          "SET counted_qty = stock_count_items.counted_qty + EXCLUDED.counted_qty, updated_at = EXCLUDED.updated_at",
          @count.id, product.id, qty, product.stock, now, now
        ]))
      end

      def invalid!(code, product = nil)
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("stock.errors.#{code}", product: product&.name),
          details: { code: code.to_s, product: product && { id: product.id, name: product.name } }
        )
      end
    end
  end
end
