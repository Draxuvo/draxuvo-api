module Push
  # «Comanda lista» al mesero de la cuenta (spec 057, US1, FR-010, FR-022, FR-024). Se llama unos segundos después de que
  # la estación marca listos artículos (ventana de agrupación) y junta en un aviso los de la comanda que quedaron listos
  # desde el último aviso de esa comanda. Si el último aviso fue hace menos de un minuto, devuelve cuándo reintentar.
  # Un grupo cuyo artículo más antiguo lleva más de 5 minutos listo ya no sirve: se registra como vencido.
  class CheckReady
    KIND = "check_ready".freeze
    MIN_GAP = 60.seconds
    EXPIRES_AFTER = 5.minutes

    Result = Struct.new(:status, :retry_at, keyword_init: true)

    def self.call(**args) = new(**args).call

    def initialize(kitchen_order_id:, actor_id: nil, now: Time.current, attempt: 1)
      @kitchen_order = KitchenOrder.includes(check: %i[company dining_table waiter]).find_by(id: kitchen_order_id)
      @actor_id = actor_id
      @now = now
      @attempt = attempt
    end

    def call
      return result(:skipped) unless @kitchen_order

      check = @kitchen_order.check
      company = check.company
      waiter = check.waiter
      return result(:skipped) if waiter.nil? || waiter.id == @actor_id || !Eligibility.company_ok?(company, KIND)

      last = last_sent_at(company)
      return Result.new(status: :retry, retry_at: last + MIN_GAP) if last && last > @now - MIN_GAP

      items = ready_items(last)
      return result(:nothing) if items.empty?

      if items.minimum(:ready_at) < @now - EXPIRES_AFTER
        Deliver.record(company: company, user: waiter, kind: KIND, subject_key: subject_key, status: "expired", attempts: @attempt)
        return result(:expired)
      end

      Deliver.call(company: company, user: waiter, message: message(check, items.count), subject_key: subject_key, attempt: @attempt)
      result(:sent)
    end

    private

    def subject_key = "kitchen_order:#{@kitchen_order.id}"

    def result(status) = Result.new(status: status)

    def last_sent_at(company)
      PushDelivery.sent.where(company: company, kind: KIND, subject_key: subject_key).maximum(:created_at)
    end

    def ready_items(since)
      scope = @kitchen_order.check_items.status_ready.where.not(ready_at: nil)
      since ? scope.where("ready_at > ?", since) : scope
    end

    def message(check, count)
      body_key, args = if check.dining_table
        [ "check_ready_table", { table: Message.truncate(check.dining_table.name, 40) } ]
      else
        [ "check_ready_takeout", { name: Message.truncate(check.takeout_name, 40) } ]
      end
      Message.new(kind: KIND, company: check.company, path: "/pedido?cuenta=#{check.id}&hoja=1", subject_id: check.id,
                  body_key: body_key, body_args: args.merge(count: count))
    end
  end
end
