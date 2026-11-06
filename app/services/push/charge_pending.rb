module Push
  # «Por cobrar» a dueño y administradores (spec 058, FR-021): una venta pasó a cobro, una orden de trabajo quedó terminada
  # o un mesero pidió el cobro de una cuenta, con «Cobro solo por jefes» encendido. No le llega a quien hizo la acción.
  # Sin montos ni datos del cliente: la venta lleva el nombre del cajero, la orden su número y la cuenta su mesa o, si es
  # para llevar, su número (no el nombre del cliente). La `subject_key` lleva la hora del hecho: si una venta se regresa y
  # se vuelve a pasar a cobro, se avisa de nuevo.
  class ChargePending
    KIND = "charge_pending".freeze
    TYPES = %w[sale work_order check].freeze

    def self.call(**args) = new(**args).call

    def initialize(subject_type:, subject_id:, actor_id: nil, attempt: 1)
      @type = subject_type.to_s
      @subject = load_subject(subject_id)
      @actor_id = actor_id
      @attempt = attempt
    end

    def call
      return :skipped unless @subject && pending?

      company = @subject.company
      return :skipped unless Eligibility.company_ok?(company, KIND)

      message = build_message(company)
      company.user_companies.where(role: %i[owner admin]).includes(:user).each do |membership|
        next if membership.user_id == @actor_id

        Deliver.call(company: company, user: membership.user, message: message, subject_key: subject_key, attempt: @attempt)
      end
      :sent
    end

    # Para el registro de un envío que falló tras los reintentos.
    def subject_key
      case @type
      when "sale" then "sale:#{@subject.id}:#{@subject.submitted_at.to_i}"
      when "work_order" then "work_order:#{@subject.id}:done:#{@subject.completed_at.to_i}"
      else "check:#{@subject.id}:#{@subject.charge_requested_at.to_i}"
      end
    end

    attr_reader :subject

    private

    def load_subject(id)
      case @type
      when "sale" then Sale.includes(:company, :opened_by).find_by(id: id)
      when "work_order" then WorkOrder.includes(:company).find_by(id: id)
      when "check" then Check.includes(:company, :dining_table).find_by(id: id)
      end
    end

    # Para cuando corre el job, lo que se avisa puede ya no estar pendiente (cobrado, regresado o con más artículos).
    def pending?
      case @type
      when "sale" then @subject.submitted?
      when "work_order" then @subject.done?
      else @subject.charge_requested?
      end
    end

    def build_message(company)
      case @type
      when "sale"
        Message.new(kind: KIND, company: company, path: "/venta?venta=#{@subject.id}", subject_id: @subject.id,
                    body_key: "charge_pending_sale", body_args: { cashier: Message.truncate(@subject.opened_by.full_name, 40) })
      when "work_order"
        Message.new(kind: KIND, company: company, path: "/ordenes/#{@subject.id}", subject_id: @subject.id,
                    body_key: "charge_pending_work_order", body_args: { number: @subject.id })
      else
        key, args = if @subject.takeout?
          [ "charge_pending_takeout", { number: @subject.id } ]
        else
          [ "charge_pending_table", { table: Message.truncate(@subject.dining_table.name, 40) } ]
        end
        Message.new(kind: KIND, company: company, path: "/pedido?cuenta=#{@subject.id}&hoja=1", subject_id: @subject.id,
                    body_key: key, body_args: args)
      end
    end
  end
end
