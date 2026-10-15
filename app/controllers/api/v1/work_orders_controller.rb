module Api
  module V1
    class WorkOrdersController < BaseController
      include Idempotent

      requires_module :work_orders
      idempotent :create_note, :create_photo

      TRANSITIONS = %w[start finish reopen cancel charge void_charge].freeze
      ORDER_TIME_ZONE = "America/Mexico_City".freeze

      before_action :require_boss!,  only: [ :create, :update ]
      before_action :require_admin!, only: [ :destroy ]

      def index
        orders = base_scope.includes(:employee, :work_order_items, :work_order_steps)
        orders = search(orders, params[:search])

        if params[:status].present?
          raise invalid_param(:status) unless WorkOrder.statuses.key?(params[:status])
          orders = orders.where(status: params[:status])
        end
        orders = orders.where(employee_id: params[:employee_id]) if params[:employee_id].present?
        orders = orders.where(priority: params[:priority])       if params[:priority].present?
        orders = orders.where(employee_id: nil) if params[:unassigned] == "true" && !staff?
        orders = filter_paid_on(orders, params[:paid_on]) if params[:paid_on].present?

        orders = if params[:sort_by] == "urgency" || (staff? && params[:sort_by].blank?)
          urgency_order(orders)
        else
          apply_sort(orders, allowed: %i[title priority status due_date created_at],
                             default: :created_at, default_dir: :desc)
        end

        @pagy, orders = pagy(orders)
        render json: paginate_response(@pagy, orders.map { |o| WorkOrderSerializer.new(o).as_json })
      end

      def summary
        scope = base_scope
        counts = scope.group(:status).count
        today = paid_on_range(Time.find_zone(ORDER_TIME_ZONE).today)
        render json: {
          counts: {
            open:        counts["open"].to_i,
            in_progress: counts["in_progress"].to_i,
            done:        counts["done"].to_i,
            paid_today:  filter_paid_on(scope.where(status: :paid), today).count,
            cancelled:   counts["cancelled"].to_i,
            unassigned:  scope.where(employee_id: nil, status: %i[open in_progress done]).count
          },
          to_charge_total: scope.where(status: :done).sum(:total)
        }
      end

      def show
        render_order(base_scope.find(params[:id]))
      end

      def create
        order = current_company.work_orders.build(work_order_params)
        order.created_by = current_user

        WorkOrder.transaction do
          order.save!
          event(order, :created)
          build_items(order, params[:items]) if params[:items].present?
          build_steps(order, params[:steps]) if params[:steps].present? && current_company.order_mode_service?
        end

        render_order(order.reload, status: :created)
      end

      def update
        order = base_scope.find(params[:id])
        ensure_unlocked!(order)

        WorkOrder.transaction do
          order.assign_attributes(work_order_params)
          previous_employee_id = order.employee_id_was
          employee_changed = order.employee_id_changed?
          order.save!
          if employee_changed
            event(order, :reassigned, { from_employee_id: previous_employee_id, to_employee_id: order.employee_id })
          end
          rebuild_items(order, params[:items]) if params.key?(:items)
          rebuild_steps(order, params[:steps]) if params.key?(:steps)
        end

        render_order(order.reload)
      end

      def destroy
        order = base_scope.find(params[:id])
        raise unprocessable(I18n.t("work_order.locked")) if order.paid?

        order.destroy!
        render json: { message: I18n.t("work_order.deleted") }
      end

      # POST /api/v1/work_orders/:id/{start|finish|reopen|cancel|charge|void_charge}
      def transition
        order  = base_scope.find(params[:id])
        action = request.path_parameters[:transition].to_s
        raise ApiErrors::NotFoundError.new unless TRANSITIONS.include?(action)

        WorkOrders::Transition.call(order, action, work_order_context,
                                    params.permit(:payment_method, :amount_received, :reason))
        render_order(order)
      end

      # POST /api/v1/work_orders/:id/items
      def create_item
        order = base_scope.find(params[:id])
        ensure_unlocked!(order)

        attrs =
          if staff?
            forbid! unless current_company.order_mode_service?
            product = current_company.products.find_by(id: params[:product_id]) if params[:product_id].present?
            raise unprocessable(I18n.t("work_order.catalog_item_required")) unless product

            { product_id: product.id, description: product.name, unit: params[:unit].presence,
              unit_price: product.price, quantity: params[:quantity] || 1 }
          else
            item_attributes(params, order.work_order_items.count)
          end

        order.work_order_items.create!(attrs.merge(position: params[:position] || order.work_order_items.count))
        render_order(order.reload, status: :created)
      end

      # PATCH /api/v1/work_orders/:id/items/:item_id
      def update_item
        order = base_scope.find(params[:id])
        require_boss!
        ensure_unlocked!(order)

        order.work_order_items.find(params[:item_id]).update!(item_params)
        render_order(order.reload)
      end

      # DELETE /api/v1/work_orders/:id/items/:item_id
      def destroy_item
        order = base_scope.find(params[:id])
        require_boss!
        ensure_unlocked!(order)

        order.work_order_items.find(params[:item_id]).destroy!
        render_order(order.reload)
      end

      # POST /api/v1/work_orders/:id/steps
      def create_step
        order = base_scope.find(params[:id])
        require_boss!
        ensure_unlocked!(order)

        order.work_order_steps.create!(description: params[:description],
                                       position: params[:position] || order.work_order_steps.count)
        render_order(order.reload, status: :created)
      end

      # PATCH /api/v1/work_orders/:id/steps/:step_id
      def update_step
        order = base_scope.find(params[:id])
        step  = order.work_order_steps.find(params[:step_id])
        require_boss! if params.key?(:description) || params.key?(:position)
        ensure_unlocked!(order)

        WorkOrderStep.transaction do
          step.update!(params.permit(:description, :position)) if params.key?(:description) || params.key?(:position)
          if params.key?(:done)
            forbid! unless work_order_context.boss? || work_order_context.assigned_to?(order)
            ActiveModel::Type::Boolean.new.cast(params[:done]) ? step.mark_done!(current_user) : step.mark_undone!
          end
        end
        render_order(order.reload)
      end

      # DELETE /api/v1/work_orders/:id/steps/:step_id
      def destroy_step
        order = base_scope.find(params[:id])
        require_boss!
        ensure_unlocked!(order)

        order.work_order_steps.find(params[:step_id]).destroy!
        render_order(order.reload)
      end

      # POST /api/v1/work_orders/:id/notes
      def create_note
        order = base_scope.find(params[:id])
        event(order, :note, { "text" => params[:text].to_s.strip })
        render_order(order.reload, status: :created)
      end

      # POST /api/v1/work_orders/:id/photos
      def create_photo
        order = base_scope.find(params[:id])

        photo = order.work_order_attachments.new(uploaded_by: current_user, description: params[:description].presence)
        photo.file.attach(params[:file]) if params[:file].present?
        unless photo.save
          raise unprocessable(photo.errors[:file].first || photo.errors[:base].first || photo.errors.full_messages.first)
        end
        event(order, :photo, { attachment_id: photo.id })

        render_order(order.reload, status: :created)
      end

      # DELETE /api/v1/work_orders/:id/photos/:photo_id
      def destroy_photo
        order = base_scope.find(params[:id])
        photo = order.work_order_attachments.find(params[:photo_id])
        forbid! unless !staff? || (photo.uploaded_by_type == "User" && photo.uploaded_by_id == current_user.id)

        photo.destroy!
        render_order(order.reload)
      end

      private

      def staff?
        current_role == "staff"
      end

      # Staff ve solo sus órdenes en esta empresa; sin empleado ligado, ninguna. Todos los demás ven todas.
      def base_scope
        scope = current_company.work_orders
        return scope unless staff?

        current_employee ? scope.where(employee: current_employee) : scope.none
      end

      def render_order(order, status: :ok)
        render json: WorkOrderSerializer.new(order, detailed: true, context: work_order_context).as_json, status: status
      end

      def event(order, kind, data = {})
        order.work_order_events.create!(kind: kind, actor: current_user, data: data)
      end

      def unprocessable(message, details: nil)
        ApiErrors::UnprocessableEntityError.new(message: message, details: details)
      end

      def invalid_param(name)
        unprocessable(I18n.t("errors.unprocessable"), details: "#{name} invalid")
      end

      def ensure_unlocked!(order)
        raise unprocessable(I18n.t("work_order.locked")) if order.locked?
      end

      def search(scope, query)
        return scope if query.blank?

        scope.where("work_orders.title ILIKE :q OR work_orders.description ILIKE :q OR " \
                    "work_orders.customer_name ILIKE :q OR work_orders.customer_phone ILIKE :q",
                    q: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      end

      def urgency_order(scope)
        scope.order(priority: :desc).order(Arel.sql("work_orders.due_date ASC NULLS LAST"), created_at: :desc)
      end

      # Cobradas ese día (por tickets.paid_at, America/Mexico_City). Acepta una fecha o un rango ya calculado.
      def filter_paid_on(scope, value)
        range = value.is_a?(Range) ? value : paid_on_range(parse_date(value))
        scope.joins(:ticket).where(tickets: { status: :paid, paid_at: range })
      end

      def paid_on_range(date)
        zone = Time.find_zone(ORDER_TIME_ZONE)
        zone.local(date.year, date.month, date.day).all_day
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue ArgumentError
        raise invalid_param(:paid_on)
      end

      def work_order_params
        params.require(:work_order).permit(
          :title, :description, :priority, :due_date, :notes, :employee_id,
          :customer_name, :customer_phone, :customer_address
        ).tap do |p|
          p[:employee_id] = nil if p.key?(:employee_id) && (p[:employee_id].blank? || p[:employee_id].to_i.zero?)
        end
      end

      def item_attributes(item, idx)
        product = current_company.products.find_by(id: item[:product_id]) if item[:product_id].present?
        {
          description: item[:description].presence || product&.name,
          quantity:    item[:quantity] || 1,
          unit:        item[:unit].presence,
          position:    item[:position] || idx,
          product_id:  product&.id,
          unit_price:  item[:unit_price].presence || product&.price
        }
      end

      def build_items(order, items)
        items.each_with_index { |item, idx| order.work_order_items.create!(item_attributes(item, idx)) }
        order.recalculate_total!
      end

      def rebuild_items(order, items)
        items = Array(items)
        order.work_order_items.where.not(id: items.filter_map { |i| i[:id]&.to_i }).destroy_all

        items.each_with_index do |item, idx|
          attrs = item_attributes(item, idx)
          if item[:id].present?
            order.work_order_items.find(item[:id]).update!(attrs)
          else
            order.work_order_items.create!(attrs)
          end
        end
        order.recalculate_total!
      end

      def build_steps(order, steps)
        steps.each_with_index do |step, idx|
          order.work_order_steps.create!(description: step[:description], position: step[:position] || idx)
        end
      end

      def rebuild_steps(order, steps)
        steps = Array(steps)
        order.work_order_steps.where.not(id: steps.filter_map { |s| s[:id]&.to_i }).destroy_all

        steps.each_with_index do |step, idx|
          if step[:id].present?
            order.work_order_steps.find(step[:id]).update!(description: step[:description], position: step[:position] || idx)
          else
            order.work_order_steps.create!(description: step[:description], position: step[:position] || idx)
          end
        end
      end

      def item_params
        params.permit(:description, :quantity, :unit, :unit_price, :position, :product_id)
      end
    end
  end
end
