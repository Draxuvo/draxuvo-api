module Api
  module V1
    module Restaurant
      class ChecksController < BaseController
        before_action :require_boss!, only: %i[update waiters]

        # Cuentas canceladas para el filtro «Canceladas» (spec 070). Un jefe ve todas; el personal, las que atendió.
        def index
          unless params[:status] == "cancelled"
            raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("errors.unprocessable"), details: "status invalid")
          end

          checks = checks_scope.status_cancelled.includes(:dining_table, :waiter, :cancelled_by)
          checks = if restaurant_context.boss?
            params[:waiter_id].present? ? checks.where(waiter_id: params[:waiter_id]) : checks
          else
            checks.where(waiter_id: current_user.id)
          end
          checks = search_checks(checks, params[:search]) if params[:search].present?

          @pagy, page = pagy(checks.order(closed_at: :desc, id: :desc))
          counts = CheckItem.status_cancelled.where(check_id: page.map(&:id)).group(:check_id).count
          render json: paginate_response(@pagy, page.map { |c|
            CheckSerializer.cancelled_summary(c, restaurant_context, cancelled_items: counts.fetch(c.id, 0))
          })
        end

        def create
          check = open_check
          render json: serialize_check(check), status: :created
        rescue ActiveRecord::RecordNotUnique
          invalid!(:table_occupied)
        end

        def show
          check = find_check
          return unless stale?(etag: [ current_user.id, current_role, check.updated_at, check.check_items.maximum(:updated_at),
                                       check.check_items.count, check.check_payments.count, check.ticket&.id ])

          render json: serialize_check(check)
        end

        # Personas de la empresa a quienes se puede reasignar una cuenta (FR-005).
        def waiters
          people = current_company.users.where(active: true).order(:first_name, :last_name)
          render json: { results: people.map { |u| { id: u.id, name: u.full_name } } }
        end

        # Reasignar mesero (FR-005).
        def update
          check = find_check
          invalid!(:check_not_open) unless check.status_open?
          waiter = current_company.users.find_by(id: params[:waiter_id]) or invalid!(:waiter_not_member)
          check.update!(waiter: waiter)
          render json: serialize_check(check)
        end

        # Solo una cuenta sin renglones vigentes: vacía, con borradores o con todo cancelado (FR-032, spec 068).
        def cancel
          check = find_check
          Check.transaction do
            check.lock!
            invalid!(:check_not_open) unless check.status_open?
            TerminalCharge.ensure_none_open!(check) # spec 069
            forbid! unless restaurant_context.boss? || restaurant_context.waiter_of?(check)
            invalid!(:has_sent_items) unless ::Restaurant::Permissions.releasable?(check)

            check.check_items.status_draft.destroy_all
            check.update!(status: :cancelled, closed_at: Time.current, cancel_reason: params[:reason].to_s.strip.presence,
                          cancelled_by: current_user)
          end
          render json: serialize_check(check.reload)
        end

        private

        # Mesa, nombre para llevar o mesero (spec 070).
        def search_checks(checks, term)
          like = "%#{ActiveRecord::Base.sanitize_sql_like(term.to_s.strip)}%"
          checks.left_joins(:dining_table).joins(:waiter).where(
            "dining_tables.name ILIKE :q OR checks.takeout_name ILIKE :q OR " \
            "CONCAT_WS(' ', users.first_name, users.last_name) ILIKE :q", q: like
          )
        end

        def open_check
          attrs = { opened_by: current_user, waiter: current_user, opened_at: Time.current }
          if params[:dining_table_id].present?
            table = current_company.dining_tables.find(params[:dining_table_id])
            invalid!(:table_occupied) if table.occupied?
            checks_scope.create!(attrs.merge(dining_table: table))
          else
            checks_scope.create!(attrs.merge(takeout_name: params[:takeout_name].to_s.strip))
          end
        end
      end
    end
  end
end
