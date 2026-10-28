module Api
  module V1
    # Alertas operativas (spec 045): comandas, órdenes, mesas y stock que piden atención. Solo para dueño y
    # administrador. Se calculan al leer (Alerts::Collector); paginan como el resto de las listas.
    class AlertsController < BaseController
      before_action :require_boss!

      DEFAULT_PAGE_SIZE = 50
      MAX_PAGE_SIZE = 100

      # GET /api/v1/alerts
      def index
        result = Alerts::Collector.new(current_company).call
        pagy = build_pagy(result.results.size)
        page = result.results[pagy.offset, pagy.vars[:limit]] || []

        render json: paginate_response(pagy, page.map { |alert| AlertSerializer.new(alert).as_json }).merge(
          count: result.results.size,
          snoozed: pagy.page == 1 ? result.snoozed.map { |alert, snooze| AlertSerializer.new(alert, snooze: snooze).as_json } : []
        )
      end

      private

      # Pagy no trae el extra de arreglos: la página se corta a mano y se ajusta al rango para no fallar con un `page` alto.
      def build_pagy(count)
        limit = params[:page_size].to_i
        limit = DEFAULT_PAGE_SIZE unless limit.positive?
        limit = [ limit, MAX_PAGE_SIZE ].min
        pages = [ (count.to_f / limit).ceil, 1 ].max
        Pagy.new(count: count, page: params[:page].to_i.clamp(1, pages), limit: limit)
      end
    end
  end
end
