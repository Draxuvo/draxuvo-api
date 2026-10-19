# La estación avanza sus artículos: nuevo -> en preparación -> listo (FR-014, FR-015).
# No salta ni retrocede, y si otro dispositivo ya lo movió responde 422 invalid_transition.
module Restaurant
  class AdvanceItems
    NEXT = { "new" => "preparing", "preparing" => "ready" }.freeze
    STAMP = { "preparing" => :preparing_at, "ready" => :ready_at }.freeze

    # Un artículo de la estación.
    def self.item(station, item_id)
      CheckItem.transaction do
        item = station.check_items.lock.find(item_id)
        [ advance!(item) ]
      end
    end

    # Todos los artículos de una comanda en esa estación, cada uno al siguiente estado.
    def self.order(station, kitchen_order_id)
      CheckItem.transaction do
        items = station.check_items.where(kitchen_order_id: kitchen_order_id, status: NEXT.keys.map { |s| CheckItem.statuses.fetch(s) })
                       .order(:id).lock.to_a
        raise invalid_transition if items.empty?

        items.map { |item| advance!(item) }
      end
    end

    def self.advance!(item)
      target = NEXT[item.status]
      raise invalid_transition unless target && item.check.status_open?

      item.update!(status: target, STAMP.fetch(target) => Time.current)
      item
    end

    def self.invalid_transition
      ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("restaurant.errors.invalid_transition"), details: { code: "invalid_transition" }
      )
    end
  end
end
