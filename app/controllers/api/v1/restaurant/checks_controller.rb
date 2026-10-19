module Api
  module V1
    module Restaurant
      class ChecksController < BaseController
        before_action :require_boss!, only: %i[update waiters]

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

        # Solo una cuenta sin artículos mandados (FR-032).
        def cancel
          check = find_check
          Check.transaction do
            check.lock!
            invalid!(:check_not_open) unless check.status_open?
            forbid! unless restaurant_context.boss? || restaurant_context.waiter_of?(check)
            invalid!(:has_sent_items) if check.check_items.where.not(status: :draft).exists?

            check.check_items.status_draft.destroy_all
            check.update!(status: :cancelled, closed_at: Time.current, cancel_reason: params[:reason].to_s.strip.presence)
          end
          render json: serialize_check(check.reload)
        end

        private

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
