# app/controllers/api/v1/work_orders_controller.rb
module Api
  module V1
    class WorkOrdersController < BaseController
      requires_module :work_orders

      before_action :require_admin!, only: [ :destroy ]

      def index
        orders = base_scope.includes(:employee, :work_order_items)
                           .search(params[:search])

        orders = orders.where(status: params[:status])           if params[:status].present?
        orders = orders.where(employee_id: params[:employee_id]) if params[:employee_id].present?
        orders = orders.where(priority: params[:priority])       if params[:priority].present?

        orders = apply_sort(orders,
                   allowed: %i[title priority status due_date created_at],
                   default: :created_at, default_dir: :desc)

        @pagy, orders = pagy(orders)
        render json: paginate_response(@pagy, orders.map { |o| WorkOrderSerializer.new(o).as_json })
      end

      def show
        order = base_scope.find(params[:id])
        render json: WorkOrderSerializer.new(order, detailed: true).as_json
      end

      def create
        order = current_company.work_orders.build(work_order_params)
        order.created_by = current_user
        order.status     = :pending

        WorkOrder.transaction do
          order.save!
          build_items(order, params[:items]) if params[:items].present?
        end

        render json: WorkOrderSerializer.new(order, detailed: true).as_json, status: :created
      end

      def update
        order = base_scope.find(params[:id])

        WorkOrder.transaction do
          order.update!(work_order_params)
          rebuild_items(order, params[:items]) if params[:items].present?

          # Marcar completada
          if order.completed? && order.completed_at.nil?
            order.update_column(:completed_at, Time.current)
          end
        end

        render json: WorkOrderSerializer.new(order, detailed: true).as_json
      end

      def destroy
        order = base_scope.find(params[:id])
        order.destroy!
        render json: { message: "Orden eliminada" }
      end

      # PATCH /api/v1/work_orders/:id/status
      def update_status
        order = base_scope.find(params[:id])
        raise ApiErrors::UnprocessableError, I18n.t("work_order.already_cancelled") if order.cancelled?

        order.update!(status: params[:status])
        order.update_column(:completed_at, Time.current) if order.completed?
        render json: WorkOrderSerializer.new(order).as_json
      end

      # POST /api/v1/work_orders/:id/items
      def create_item
        order   = base_scope.find(params[:id])
        product = current_company.products.find_by(id: params[:product_id]) if params[:product_id].present?

        item = order.work_order_items.create!(
          description: params[:description].presence || product&.name,
          quantity:    params[:quantity] || 1,
          unit:        params[:unit].presence || product&.unit,
          position:    params[:position] || order.work_order_items.count,
          status:      :pending,
          product_id:  product&.id,
          unit_price:  params[:unit_price].presence || product&.price
        )

        render json: WorkOrderSerializer.new(order.reload, detailed: true).as_json, status: :created
      end

      # PATCH /api/v1/work_orders/:id/items/:item_id
      def update_item
        order = base_scope.find(params[:id])
        item  = order.work_order_items.find(params[:item_id])

        item.update!(item_params)

        render json: WorkOrderSerializer.new(order.reload, detailed: true).as_json
      end

      # DELETE /api/v1/work_orders/:id/items/:item_id
      def destroy_item
        order = base_scope.find(params[:id])
        item  = order.work_order_items.find(params[:item_id])
        item.destroy!

        render json: WorkOrderSerializer.new(order.reload, detailed: true).as_json
      end

      # PATCH /api/v1/work_orders/:id/items/:item_id/toggle
      def toggle_item
        order = base_scope.find(params[:id])
        item  = order.work_order_items.find(params[:item_id])
        new_status = item.completed? ? :pending : :completed
        item.update!(
          status:       new_status,
          completed_at: new_status == :completed ? Time.current : nil
        )
        render json: WorkOrderSerializer.new(order, detailed: true).as_json
      end

      private

      # Todos los roles ven todas las órdenes de la compañía
      def base_scope
        current_company.work_orders
      end

      def work_order_params
        params.require(:work_order).permit(
          :title, :description, :priority,
          :status, :due_date, :notes, :employee_id
        ).tap do |p|
          p[:employee_id] = nil if p[:employee_id].blank? || p[:employee_id].to_i.zero?
        end
      end

      def build_items(order, items)
        items.each_with_index do |item, idx|
          product = current_company.products.find_by(id: item[:product_id]) if item[:product_id].present?

          order.work_order_items.create!(
            description: item[:description].presence || product&.name,
            quantity:    item[:quantity] || 1,
            unit:        item[:unit].presence || product&.unit,
            position:    item[:position] || idx,
            status:      :pending,
            product_id:  product&.id,
            unit_price:  item[:unit_price].presence || product&.price
          )
        end
        order.recalculate_total!
      end

      def rebuild_items(order, items)
        incoming_ids = items.filter_map { |i| i[:id]&.to_i }
        order.work_order_items.where.not(id: incoming_ids).destroy_all

        items.each_with_index do |item, idx|
          product = current_company.products.find_by(id: item[:product_id]) if item[:product_id].present?

          attrs = {
            description: item[:description].presence || product&.name,
            quantity:    item[:quantity] || 1,
            unit:        item[:unit].presence || product&.unit,
            position:    item[:position] || idx,
            product_id:  product&.id,
            unit_price:  item[:unit_price].presence || product&.price
          }

          if item[:id].present?
            order.work_order_items.find_by(id: item[:id])&.update!(attrs)
          else
            order.work_order_items.create!(attrs.merge(status: :pending))
          end
        end

        order.recalculate_total!
      end

      def item_params
        params.permit(:description, :quantity, :unit, :unit_price, :position, :product_id)
      end
    end
  end
end
