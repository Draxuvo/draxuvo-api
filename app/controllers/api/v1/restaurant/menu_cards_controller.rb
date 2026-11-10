module Api
  module V1
    module Restaurant
      # PDF de tarjetas QR de las mesas (spec 059, contracts/api.md). Solo dueño, administrador y super admin.
      class MenuCardsController < BaseController
        MAX_TABLES = 200

        before_action :require_boss!

        # POST /api/v1/restaurant/menu_cards/pdf — `table_ids` vacío o ausente: todas las mesas activas.
        def pdf
          tables = selected_tables
          tables.each(&:ensure_menu_token!)
          send_data ::Restaurant::MenuCardsPdf.new(company: current_company, tables: tables).call,
                    type: "application/pdf", filename: "tarjetas-qr.pdf", disposition: "attachment"
        end

        private

        def selected_tables
          active = current_company.dining_tables.active.ordered
          ids = Array(params[:table_ids]).map { |id| Integer(id.to_s, exception: false) || id }.uniq
          tables = ids.empty? ? active.to_a : active.where(id: ids.grep(Integer)).to_a

          rejected = ids - tables.map(&:id)
          if rejected.any?
            raise ApiErrors::UnprocessableEntityError.new(
              message: I18n.t("restaurant.errors.invalid_tables"), details: { code: "invalid_tables", table_ids: rejected }
            )
          end
          invalid!(:no_tables) if tables.empty?
          invalid!(:too_many_tables, max: MAX_TABLES) if tables.size > MAX_TABLES

          tables
        end
      end
    end
  end
end
