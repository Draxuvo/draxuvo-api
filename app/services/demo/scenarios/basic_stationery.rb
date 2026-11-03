# Plan Básico con el módulo extra «Punto de venta» (spec 050): una papelería con inventario, personal, asistencia, ventas de
# mostrador de la última semana (en efectivo, tarjeta y transferencia, una cancelada) y la caja lista para cobrar.
module Demo
  module Scenarios
    class BasicStationery < Base
      COMPANY_NAME = "Papelería El Lápiz (demo)".freeze
      ORDER_MODE = :service
      # Módulos extra contratados: la demo no pasa por Stripe, así que la fila se crea aquí.
      ADDONS = %i[pos].freeze

      # [sku, nombre, categoría, costo, precio, existencia, mínimo]
      PRODUCTS = [
        [ "PAP-001", "Cuaderno profesional 100 hojas", "Cuadernos", 24, 42, 60, 12 ],
        [ "PAP-002", "Cuaderno de dibujo", "Cuadernos", 18, 32, 25, 8 ],
        [ "PAP-003", "Pluma azul", "Escritura", 4, 9, 140, 30 ],
        [ "PAP-004", "Pluma negra", "Escritura", 4, 9, 120, 30 ],
        [ "PAP-005", "Lápiz del número 2", "Escritura", 3, 7, 200, 40 ],
        [ "PAP-006", "Marcatextos amarillo", "Escritura", 10, 18, 3, 8 ],
        [ "PAP-007", "Goma blanca", "Escolar", 3, 6, 90, 20 ],
        [ "PAP-008", "Sacapuntas metálico", "Escolar", 5, 10, 70, 15 ],
        [ "PAP-009", "Regla de 30 cm", "Escolar", 6, 12, 45, 10 ],
        [ "PAP-010", "Tijeras escolares", "Escolar", 14, 26, 30, 8 ],
        [ "PAP-011", "Pegamento en barra", "Escolar", 9, 17, 2, 10 ],
        [ "PAP-012", "Cartulina blanca", "Papel", 4, 8, 150, 30 ],
        [ "PAP-013", "Folder tamaño carta", "Papel", 2, 5, 180, 40 ],
        [ "PAP-014", "Hojas blancas (paquete de 100)", "Papel", 22, 38, 40, 10 ],
        [ "PAP-015", "Calculadora básica", "Oficina", 55, 95, 12, 4 ],
        [ "PAP-016", "Mochila escolar", "Oficina", 180, 320, 0, 3 ]
      ].freeze

      # Los tipos iniciales del giro «servicio» (Refacción, Material) no tienen sentido en una papelería.
      TYPE_NAMES = { "sold" => "Servicio", "counted_sold" => "Artículo", "supply" => "Insumo" }.freeze

      # Servicio sin existencia: se vende pero no se cuenta.
      SERVICE = [ "SER-001", "Copia blanco y negro", "Servicios", 0, 1.5, 0, 0 ].freeze

      # Ventas de cada día (se repiten rotando): renglones [sku, cantidad] y cómo se pagó.
      DAILY_SALES = [
        { lines: [ [ "PAP-001", 2 ], [ "PAP-003", 3 ] ], pay: :cash },
        { lines: [ [ "PAP-014", 1 ], [ "PAP-013", 5 ], [ "SER-001", 20 ] ], pay: :card },
        { lines: [ [ "PAP-005", 4 ], [ "PAP-007", 2 ], [ "PAP-008", 1 ] ], pay: :cash },
        { lines: [ [ "PAP-015", 1 ] ], pay: :transfer },
        { lines: [ [ "PAP-002", 1 ], [ "PAP-012", 6 ], [ "PAP-009", 1 ] ], pay: :cash }
      ].freeze
      DAYS = 7
      SALES_PER_DAY = 3

      def build
        rename_product_types
        employees = create_employees
        fill_attendance(employees)
        create_products
        grant_addons
        cashiers = [ owner, create_staff_user(company, "Pablo", "Cruz", position: "Cajero", department: "Ventas", salary: 11_000) ]
        create_sales(cashiers)
        pay_last_month_payroll
      end

      private

      def rename_product_types
        TYPE_NAMES.each { |kind, name| company.product_types.find_by!(kind: kind).update!(name: name) }
      end

      def create_products
        PRODUCTS.each_with_index do |row, index|
          product = create_product(row)
          product.barcodes.create!(company: company, code: format("750990%07d", index + 1))
        end
        create_product(SERVICE, product_type: company.product_types.find_by!(kind: "sold"))
      end

      def grant_addons
        subscription = company.subscription
        ADDONS.each do |key|
          subscription.addons.create!(company: company, module: key.to_s, amount_cents: Addon.find(key).monthly_amount_cents,
                                      started_at: 5.days.ago)
        end
        company.reload
      end

      def create_sales(cashiers)
        count = 0
        DAYS.downto(1) do |days_ago|
          SALES_PER_DAY.times do |slot|
            template = DAILY_SALES[(days_ago + slot) % DAILY_SALES.size]
            at = days_ago.days.ago.in_time_zone.change(hour: 10 + slot * 3, min: 15 + slot * 7)
            sale = sell(cashiers[count % cashiers.size], template, at)
            cancel(sale, at) if days_ago == 2 && slot == 1
            count += 1
          end
        end
        sell(cashiers.first, DAILY_SALES.first, Time.current.change(min: 0))
      end

      def sell(cashier, template, at)
        sale = company.sales.create!(opened_by: cashier)
        template[:lines].each do |sku, quantity|
          Sales::AddItem.call(sale, product_id: product_id(sku), quantity: quantity)
        end
        sale.reload
        result = Sales::Charge.call(sale, cashier, lock_version: sale.lock_version, payments: [ payment(template[:pay], sale.total) ])
        backdate(result.sale, at)
        result.sale
      end

      def payment(kind, total)
        case kind
        when :cash then { method: "cash", amount_received: (total / 50).ceil * 50 }
        when :card then { method: "card", amount: total }
        else { method: "transfer", amount: total, reference: "SPEI-DEMO" }
        end
      end

      def cancel(sale, at)
        Sales::Cancel.call(sale, owner, "Cliente devolvió los artículos")
        sale.reload.update_columns(cancelled_at: at + 30.minutes, updated_at: at + 30.minutes)
      end

      def product_id(sku) = product_ids.fetch(sku)

      def product_ids = @product_ids ||= company.products.pluck(:sku, :id).to_h

      # Las ventas de días pasados llevan su fecha (venta, ticket, pagos y movimientos de stock).
      def backdate(sale, at)
        sale.update_columns(created_at: at - 4.minutes, paid_at: at, updated_at: at)
        ticket = sale.ticket
        ticket.update_columns(created_at: at, paid_at: at, updated_at: at)
        ticket.ticket_payments.update_all(created_at: at, updated_at: at)
        StockMovement.where(sale_id: sale.id).update_all(created_at: at, updated_at: at)
      end
    end
  end
end
