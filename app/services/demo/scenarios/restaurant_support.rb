# Lo que comparten los escenarios de restaurante (spec 039): estaciones, mesas, menú y cuentas en cada estado.
module Demo
  module Scenarios
    module RestaurantSupport
      PEOPLE = [
        [ "Pedro Salinas", "Cocinero", "Cocina", 11_500 ],
        [ "Rosa Cabrera", "Cajera", "Salón", 10_500 ],
        [ "Iván Duarte", "Auxiliar de cocina", "Cocina", 9_000 ]
      ].freeze

      # [sku, nombre, categoría, costo, precio, existencia, mínimo, estación (:kitchen | :bar | nil), tipo]
      MENU = [
        [ "TAC", "Tacos al pastor", "Platillos", 25, 70, 0, 0, :kitchen, "sold" ],
        [ "HAM", "Hamburguesa", "Platillos", 40, 120, 0, 0, :kitchen, "sold" ],
        [ "ENS", "Ensalada de la casa", "Platillos", 22, 85, 0, 0, :kitchen, "sold" ],
        [ "SOP", "Sopa del día", "Platillos", 15, 55, 0, 0, :kitchen, "sold" ],
        [ "ENC", "Enchiladas verdes", "Platillos", 30, 95, 0, 0, :kitchen, "sold" ],
        [ "QUE", "Quesadillas", "Platillos", 18, 60, 0, 0, :kitchen, "sold" ],
        [ "PAS", "Pastel de chocolate", "Postres", 20, 65, 0, 0, :kitchen, "sold" ],
        [ "FLA", "Flan napolitano", "Postres", 14, 50, 0, 0, :kitchen, "sold" ],
        [ "HOR", "Agua de horchata", "Bebidas", 6, 25, 0, 0, :bar, "sold" ],
        [ "LIM", "Limonada", "Bebidas", 7, 28, 0, 0, :bar, "sold" ],
        [ "CER", "Cerveza artesanal", "Bebidas", 18, 60, 30, 6, :bar, "counted_sold" ],
        [ "COL", "Refresco de cola", "Bebidas", 8, 30, 24, 6, :bar, "counted_sold" ],
        [ "CAF", "Café americano", "Bebidas", 9, 35, 40, 8, :bar, "counted_sold" ],
        [ "MIN", "Agua mineral", "Bebidas", 7, 25, 36, 8, :bar, "counted_sold" ],
        [ "I-TOR", "Tortilla de maíz (kg)", "Insumos", 22, 30, 12, 4, nil, "supply" ],
        [ "I-CAR", "Carne al pastor (kg)", "Insumos", 130, 180, 18, 5, nil, "supply" ],
        [ "I-LIM", "Limones (kg)", "Insumos", 24, 35, 3, 4, nil, "supply" ],
        [ "I-ACE", "Aceite (l)", "Insumos", 38, 55, 9, 3, nil, "supply" ]
      ].freeze

      private

      def setup_restaurant(target, tables:)
        stations = { kitchen: target.stations.create!(name: "Cocina", position: 1, kind: "kitchen"),
                     bar: target.stations.create!(name: "Barra", position: 2, kind: "bar") }
        dining = (1..tables).map { |n| target.dining_tables.create!(name: n.to_s, position: n) }
        [ stations, dining ]
      end

      def create_menu(target, stations)
        types = target.product_types.index_by(&:kind)
        MENU.to_h do |sku, name, category, cost, price, stock, min, station, kind|
          product = create_product([ "R-#{sku}", name, category, cost, price, stock, min ], target: target,
                                   station: station && stations[station], product_type: types.fetch(kind))
          [ sku, product ]
        end
      end

      def waiter_context(user) = Restaurant::Permissions::Context.new(user: user, role: "staff")

      def boss_context = Restaurant::Permissions::Context.new(user: owner, role: "owner")

      # Abre una cuenta con renglones [producto, cantidad, nota] y la lleva hasta `state`:
      # :draft (sin mandar), :sent (comanda en cocina y barra), :preparing, :ready o :delivered.
      def open_check(target, waiter, items, table: nil, takeout: nil, minutes: 15, state: :delivered)
        check = Check.create!(company: target, dining_table: table, takeout_name: takeout, opened_by: waiter, waiter: waiter,
                              opened_at: minutes.minutes.ago)
        items.each do |product, quantity, note|
          check.check_items.create!(company: target, product: product, name: product.name, unit_price: product.price,
                                    quantity: quantity, note: note)
        end
        return check if state == :draft

        Restaurant::SendRound.call(check, waiter_context(waiter))
        advance(check, { sent: 0, preparing: 1, ready: 2, delivered: 2 }.fetch(state))
        deliver(check) if state == :delivered
        check.reload
      end

      def advance(check, steps)
        check.check_items.reload.each do |item|
          steps.times { Restaurant::AdvanceItems.item(item.station, item.id) } if item.station
        end
      end

      def deliver(check)
        check.check_items.reload.each { |item| item.update!(status: :delivered, delivered_at: Time.current) }
      end

      # Cobra la cuenta con los pagos dados [[método, monto, recibido o referencia]]; el último la cierra y genera el ticket.
      def pay(check, waiter, payments)
        payments.each do |method, amount, extra|
          params = { method: method, amount: amount }
          method == "cash" ? params[:amount_received] = extra : params[:reference] = extra
          Restaurant::AddPayment.call(check.reload, waiter_context(waiter), params)
        end
        check.reload
      end
    end
  end
end
