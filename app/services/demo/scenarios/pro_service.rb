# Plan Pro, servicio técnico (electricidad y plomería): órdenes de trabajo en cada estado con pasos y conceptos,
# tickets cobrados, terminales de cobro, inventario y nómina.
module Demo
  module Scenarios
    class ProService < Base
      COMPANY_NAME = "Electricidad y Plomería Volta (demo)".freeze
      ORDER_MODE = :service

      PRODUCTS = [
        [ "CAB-12", "Cable THW calibre 12 (m)", "Material eléctrico", 18.5, 25, 300, 50 ],
        [ "APA-01", "Apagador sencillo", "Material eléctrico", 22, 45, 40, 10 ],
        [ "CON-02", "Contacto doble polarizado", "Material eléctrico", 28, 55, 6, 10 ],
        [ "FOC-09", "Foco LED 9 W", "Material eléctrico", 32, 55, 0, 10 ],
        [ "INT-20", "Interruptor termomagnético 20 A", "Material eléctrico", 85, 140, 18, 5 ],
        [ "CIN-01", "Cinta aislante", "Material eléctrico", 12, 22, 60, 15 ],
        [ "TUB-34", "Tubo PVC 3/4\" (tramo)", "Plomería", 35, 60, 25, 8 ],
        [ "COD-34", "Codo PVC 3/4\"", "Plomería", 6, 12, 80, 20 ],
        [ "LLA-01", "Llave de paso 1/2\"", "Plomería", 95, 160, 3, 5 ],
        [ "MEZ-01", "Mezcladora para lavabo", "Plomería", 280, 460, 8, 3 ],
        [ "SEL-01", "Sellador de roscas", "Plomería", 18, 35, 30, 8 ],
        [ "FLT-01", "Flotador para tinaco", "Plomería", 64, 110, 2, 4 ]
      ].freeze

      SERVICES = [
        [ "SRV-VIS", "Visita de diagnóstico", "Servicios", 0, 250 ],
        [ "SRV-HORA", "Mano de obra por hora", "Servicios", 0, 300 ]
      ].freeze

      # Cada acción es [acción, parámetros]; todas las hace el dueño.
      ORDERS = [
        { title: "Instalación de contactos en cocina", priority: :high, employee: 1, due: 1,
          customer: [ "Café La Plaza", "5598765432", "Calle 5 de Mayo 10" ],
          steps: [ "Medir el cableado", "Instalar los contactos", "Probar el circuito" ], steps_done: 0, actions: [] },
        { title: "Cambio de centro de carga", priority: :urgent, employee: 1, due: 0,
          customer: [ "Laura Méndez", "5512345678", "Av. Juárez 120" ],
          steps: [ "Cortar la luz", "Desmontar el tablero", "Instalar el centro de carga" ], steps_done: 1,
          actions: [ [ :start, {} ] ], note: "El cliente pide terminar antes de las 5.", items: [ [ "INT-20", 2 ] ] },
        { title: "Revisión de tablero principal", priority: :medium, employee: 1, due: -1,
          customer: [ "Dr. Ramón Ortiz", "5587654321", "Calle Hidalgo 45" ],
          steps: [ "Revisar interruptores", "Apretar conexiones" ], steps_done: 2, items: [ [ "APA-01", 3 ] ], labor: 450,
          actions: [ [ :start, {} ], [ :finish, {} ] ] },
        { title: "Cambio de luminarias en bodega", priority: :medium, employee: 3, due: -3,
          customer: [ "Bodega San José", "5533221100", "Parque Industrial, nave 4" ],
          steps: [ "Retirar las lámparas viejas", "Instalar los focos LED" ], steps_done: 2, items: [ [ "FOC-09", 8 ] ], labor: 600,
          actions: [ [ :start, {} ], [ :finish, {} ], [ :charge, { payment_method: "cash", amount_received: 2000 } ] ],
          note: "Se dejó la bodega limpia." },
        { title: "Reparación de fuga en baño", priority: :high, employee: 2, due: -2,
          customer: [ "Familia Torres", "5544112233", "Calle Morelos 88" ],
          steps: [ "Cerrar el agua", "Cambiar la llave de paso" ], steps_done: 2, items: [ [ "LLA-01", 1 ], [ "SEL-01", 1 ] ], labor: 350,
          actions: [ [ :start, {} ], [ :finish, {} ], [ :charge, { payment_method: "card" } ] ] },
        { title: "Cableado de oficina nueva", priority: :high, employee: 4, due: 3,
          customer: [ "Despacho Ríos", "5544332211", "Insurgentes 300, piso 2" ],
          steps: [ "Tender cable", "Colocar canaletas" ], steps_done: 1, items: [ [ "CAB-12", 40 ] ], labor: 900,
          actions: [ [ :start, {} ] ] },
        { title: "Instalación de mezcladora", priority: :low, employee: nil, due: 5,
          customer: [ "Panadería El Trigal", "5566778899", "Calle Reforma 15" ],
          steps: [ "Retirar la llave anterior", "Instalar la mezcladora" ], steps_done: 0, actions: [] },
        { title: "Cotización de tinaco", priority: :low, employee: 2, due: 2,
          customer: [ "Sra. Patricia Vega", "5522334455", "Privada Las Flores 3" ],
          steps: [ "Medir el espacio" ], steps_done: 0,
          actions: [ [ :cancel, { reason: "El cliente decidió esperar" } ] ] }
      ].freeze

      def build
        employees = create_employees
        fill_attendance(employees)
        products = PRODUCTS.map { |row| create_product(row) }
        create_services
        create_terminals
        create_orders(employees, products)
        pay_last_month_payroll
      end

      private

      def create_services
        type = company.product_types.find_by!(kind: "sold")
        SERVICES.each do |sku, name, category, cost, price|
          Product.create!(company: company, sku: sku, name: name, category: category, unit_cost: cost, price: price,
                          stock: 0, min_stock: 0, product_type: type)
        end
      end

      def create_terminals
        company.payment_terminals.create!(name: "BBVA caja 1", provider: "bbva")
        company.payment_terminals.create!(name: "Clip móvil", provider: "clip")
      end

      def create_orders(employees, products)
        context = WorkOrders::Transition::Context.new(user: owner, role: "owner", employee: nil)
        ORDERS.each do |spec|
          order = build_order(spec, employees, products)
          spec[:actions].each { |action, params| WorkOrders::Transition.call(order, action, context, params) }
        end
      end

      def build_order(spec, employees, products)
        order = WorkOrder.create!(
          company: company, created_by: owner, employee: spec[:employee] && employees[spec[:employee]],
          title: spec[:title], priority: spec[:priority], due_date: spec[:due].days.from_now,
          customer_name: spec.dig(:customer, 0), customer_phone: spec.dig(:customer, 1), customer_address: spec.dig(:customer, 2)
        )
        order.work_order_events.create!(kind: :created, actor: owner)
        add_items(order, spec, products)
        add_steps(order, spec)
        order.work_order_events.create!(kind: :note, actor: owner, data: { "text" => spec[:note] }) if spec[:note]
        order
      end

      def add_items(order, spec, products)
        position = 0
        Array(spec[:items]).each do |sku, quantity|
          WorkOrderItem.create!(work_order: order, product: products.find { |product| product.sku == sku }, quantity: quantity,
                                unit: "pza", position: position)
          position += 1
        end
        return unless spec[:labor]

        WorkOrderItem.create!(work_order: order, description: "Mano de obra", quantity: 1, unit: "serv",
                              unit_price: spec[:labor], position: position)
      end

      def add_steps(order, spec)
        spec[:steps].each_with_index do |description, i|
          step = WorkOrderStep.create!(work_order: order, description: description, position: i)
          step.mark_done!(owner) if i < spec[:steps_done]
        end
      end
    end
  end
end
