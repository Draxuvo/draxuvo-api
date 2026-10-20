module Api
  module V1
    class WorkOrdersController < BaseController
      include Idempotent

      requires_module :work_orders
      idempotent :create_note, :create_photo, :transition

      TRANSITIONS = %w[start finish reopen cancel charge void_charge].freeze
      ORDER_TIME_ZONE = "America/Mexico_City".freeze

      before_action :require_boss!,  only: [ :update ]
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

      # El staff (spec 015) crea órdenes asignadas a sí mismo, solo con productos del catálogo y sin pasos.
      def create
        order = current_company.work_orders.build(staff? ? staff_order_params : work_order_params)
        order.created_by = current_user

        WorkOrder.transaction do
          order.save!
          event(order, :created)
          if staff?
            build_catalog_items(order, params[:items]) if params[:items].present?
          else
            build_items(order, params[:items]) if params[:items].present?
            build_steps(order, params[:steps]) if params[:steps].present? && current_company.order_mode_service?
          end
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

        WorkOrders::Transition.call(order, action, work_order_context, transition_params)
        render_order(order)
      end

      # POST /api/v1/work_orders/:id/items
      def create_item
        order = base_scope.find(params[:id])
        ensure_unlocked!(order)

        attrs =
          if staff?
            catalog_item_attributes(params).merge(unit: params[:unit].presence)
          else
            item_attributes(params, order.work_order_items.count)
          end

        item = order.work_order_items.create!(attrs.merge(position: params[:position] || order.work_order_items.count))
        event(order, :item_added, { description: item.description, quantity: item.quantity })
        render_order(order.reload, status: :created)
      end

      # PATCH /api/v1/work_orders/:id/items/:item_id
      # El staff solo cambia la cantidad de los artículos de sus órdenes (spec 015, FR-003).
      def update_item
        order = base_scope.find(params[:id])
        ensure_unlocked!(order)
        attrs = item_params
        forbid! if staff? && (attrs.keys - [ "quantity" ]).any?

        item = order.work_order_items.find(params[:item_id])
        from_quantity = item.quantity
        item.update!(attrs)
        if item.quantity != from_quantity
          event(order, :item_updated, { description: item.description, from_quantity: from_quantity, to_quantity: item.quantity })
        end
        render_order(order.reload)
      end

      # DELETE /api/v1/work_orders/:id/items/:item_id
      def destroy_item
        order = base_scope.find(params[:id])
        ensure_unlocked!(order)

        item = order.work_order_items.find(params[:item_id]).destroy!
        event(order, :item_removed, { description: item.description, quantity: item.quantity })
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

      # Lo único que el staff decide al crear: qué es y quién es el cliente. Queda asignada a su empleado.
      def staff_order_params
        raise unprocessable(I18n.t("work_order.employee_required"), details: { code: "employee_required" }) unless current_employee

        params.require(:work_order).permit(:title, :description, :customer_name, :customer_phone)
              .merge(employee_id: current_employee.id)
      end

      # Artículo del catálogo con su precio: el staff no pone precios ni conceptos libres.
      def catalog_item_attributes(item)
        product = current_company.products.find_by(id: item[:product_id]) if item[:product_id].present?
        raise unprocessable(I18n.t("work_order.catalog_item_required")) unless product

        { product_id: product.id, description: product.name, unit_price: product.price, quantity: item[:quantity] || 1 }
      end

      def build_catalog_items(order, items)
        Array(items).each_with_index do |item, idx|
          order.work_order_items.create!(catalog_item_attributes(item).merge(position: idx))
        end
        order.recalculate_total!
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

      # `payments` es el cobro con varios pagos (spec 015); `payment_method` y `amount_received`, el formato anterior.
      def transition_params
        params.permit(:payment_method, :amount_received, :reason,
                      payments: %i[method amount amount_received terminal_id authorization_code card_last4 reference])
      end

      def item_params
        params.permit(:description, :quantity, :unit, :unit_price, :position, :product_id)
      end
    end
  end
end
