module Api
  module V1
    module Restaurant
      # Enlaces públicos del menú de las mesas (spec 059, contracts/api.md): la lista para imprimir tarjetas y regenerar
      # el de una mesa. Solo dueño, administrador y super admin. Sin paginar: son las mesas activas de una empresa,
      # igual que el plano (justificado en plan.md, Complexity Tracking).
      class MenuLinksController < BaseController
        before_action :require_boss!

        # GET /api/v1/restaurant/menu_links — crea el enlace de las mesas que aún no tienen (FR-002).
        def index
          tables = current_company.dining_tables.active.ordered.to_a
          tables.each(&:ensure_menu_token!)
          render json: { results: tables.map { |table| row(table) } }
        end

        # POST /api/v1/restaurant/tables/:id/menu_link — el enlace anterior deja de servir al instante (FR-003).
        def regenerate
          table = current_company.dining_tables.find(params[:id])
          invalid!(:table_inactive) unless table.active?

          table.regenerate_menu_token!
          render json: row(table)
        end

        private

        def row(table)
          { table_id: table.id, name: table.name, url: table.menu_url, generated_at: table.menu_token_generated_at }
        end
      end
    end
  end
end
