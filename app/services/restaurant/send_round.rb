# Manda los artículos sin mandar de una cuenta como una comanda nueva (FR-007 a FR-011, FR-041).
# Un artículo controlado que ya no alcanza se rechaza y se queda sin mandar; el resto sale.
module Restaurant
  class SendRound
    Result = Struct.new(:kitchen_order, :sent, :rejected, keyword_init: true)

    def self.call(check, context) = new(check, context).call

    def initialize(check, context)
      @check = check
      @context = context
    end

    def call
      Check.transaction do
        @check.lock!
        invalid!(:check_not_open) unless @check.status_open?

        drafts = @check.check_items.status_draft.includes(:product).order(:id).to_a
        invalid!(:nothing_to_send) if drafts.empty?

        sent, rejected = split_by_availability(drafts)
        Result.new(kitchen_order: sent.any? ? send_items(sent) : nil, sent: sent, rejected: rejected)
      end
    end

    private

    # Bloquea los productos controlados (en orden, para no cruzar bloqueos entre mesas) y reparte
    # lo que alcanza contra lo disponible en ese momento.
    def split_by_availability(drafts)
      ids = drafts.filter_map(&:product_id).uniq.sort
      products = Product.where(id: ids).order(:id).lock.index_by(&:id)
      availability = Availability.new(@check.company)
      left = {}
      sent = []
      rejected = []
      drafts.each do |item|
        product = products[item.product_id]
        if product&.tracks_stock?
          left[product.id] ||= availability.available_qty(product)
          if item.quantity > left[product.id]
            rejected << [ item, [ left[product.id], 0 ].max ]
            next
          end
          left[product.id] -= item.quantity
        end
        sent << item
      end
      [ sent, rejected ]
    end

    def send_items(items)
      default_station = Station.default_for(@check.company)
      order = @check.kitchen_orders.create!(company: @check.company, sent_by: @context.user, sent_at: Time.current,
                                            number: @check.next_round_number)
      items.each do |item|
        station = item.product&.station if item.product&.station&.active?
        station ||= default_station
        invalid!(:station_required) unless station
        item.update!(status: :new, kitchen_order: order, station: station)
      end
      order
    end

    def invalid!(code)
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("restaurant.errors.#{code}"), details: { code: code.to_s }
      )
    end
  end
end
