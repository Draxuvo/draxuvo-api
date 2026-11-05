module Push
  # «Orden asignada» a quien queda como responsable (spec 057, US3, FR-011 y FR-011a). Sale una vez por asignación
  # (FR-024) y no sale si esa persona hizo el cambio, si ya no es la responsable o si su ficha está inactiva o sin
  # usuario. Con el módulo de asistencia, solo con el turno abierto (entrada de hoy sin salida, en la zona horaria del
  # negocio); sin turno se registra «fuera de turno» y no se guarda para después. Sin datos del cliente (FR-016).
  class WorkOrderAssigned
    KIND = "work_order_assigned".freeze

    def self.call(**args) = new(**args).call

    def initialize(work_order_id:, employee_id:, actor_id: nil, now: Time.current, attempt: 1)
      @order = WorkOrder.includes(:company, employee: :user).find_by(id: work_order_id)
      @employee_id = employee_id
      @actor_id = actor_id
      @now = now
      @attempt = attempt
    end

    def call
      return :skipped unless @order && @order.employee_id == @employee_id

      employee = @order.employee
      user = employee&.user
      company = @order.company
      return :skipped if user.nil? || !employee.active? || user.id == @actor_id || !Eligibility.company_ok?(company, KIND)

      if company.module_active?(:attendance) && !on_shift?(employee, company)
        Deliver.record(company: company, user: user, kind: KIND, subject_key: subject_key, status: "off_shift", attempts: @attempt)
        return :off_shift
      end

      Deliver.call(company: company, user: user, message: message(company), subject_key: subject_key, attempt: @attempt)
      :sent
    end

    private

    def subject_key = "work_order:#{@order.id}"

    def on_shift?(employee, company)
      today = @now.in_time_zone(AlertSetting.for(company).time_zone).all_day
      employee.attendances.where(company: company, checkout_at: nil, checkin_at: today).exists?
    end

    def message(company)
      title = Message.truncate(@order.title)
      body_key, args = title.present? ? [ "work_order_assigned", { number: @order.id, title: title } ] : [ "work_order_assigned_untitled", { number: @order.id } ]
      Message.new(kind: KIND, company: company, path: "/ordenes/#{@order.id}", subject_id: @order.id, body_key: body_key, body_args: args)
    end
  end
end
