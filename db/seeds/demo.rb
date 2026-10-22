# Datos de demo para navegar el panel en desarrollo. Idempotente: una empresa que ya tiene
# empleados no se vuelve a llenar. Se carga desde db/seeds.rb solo en development.
# Para regenerarlos (por ejemplo, para que la asistencia de "hoy" sea de hoy): bin/rails db:reset
#
# Contraseña de todos los usuarios de demo: Demo12345*
# El rol es por empresa (user_companies.role). multi@demo.demo es owner de Volta y staff de Sazón,
# y Sazón (plan Empresa) tiene la sucursal "Restaurante Sazón Centro".
# Sazón (con su sucursal) y Aroma trabajan en modo "order" (pedidos de mesa); Volta, Don Chuy y Plomería en "service".

DEMO_PASSWORD = "Demo12345*".freeze

DEMO_COMPANIES = [
  { name: "Abarrotes Don Chuy", slug: "abarrotes-don-chuy", domain: "donchuy.demo",
    plan: :basic, status: :active, billing_cycle: :monthly, order_mode: :service },
  { name: "Electricidad Volta", slug: "electricidad-volta", domain: "volta.demo",
    plan: :pro, status: :active, billing_cycle: :monthly, order_mode: :service },
  { name: "Restaurante Sazón", slug: "restaurante-sazon", domain: "sazon.demo",
    plan: :enterprise, status: :active, billing_cycle: :annual, order_mode: :order },
  { name: "Café Aroma", slug: "cafe-aroma", domain: "aroma.demo",
    plan: :pro, status: :trialing, trial_days_left: 10, order_mode: :order },
  { name: "Plomería Rápida", slug: "plomeria-rapida", domain: "plomeria.demo",
    plan: :pro, status: :expired, trial_days_left: -3, order_mode: :service }
].freeze

PEOPLE = [
  [ "Ana", "López", "Encargada", "Operación" ],
  [ "Luis", "Martínez", "Técnico", "Campo" ],
  [ "María", "Hernández", "Cajera", "Ventas" ],
  [ "Jorge", "García", "Ayudante", "Campo" ],
  [ "Sofía", "Ramírez", "Almacenista", "Almacén" ]
].freeze

PRODUCTS = [
  [ "CAB-12", "Cable THW calibre 12 (m)", "Material eléctrico", 18.5, 25.0, 300, 50 ],
  [ "APA-01", "Apagador sencillo", "Material eléctrico", 22.0, 45.0, 40, 10 ],
  [ "CON-02", "Contacto doble polarizado", "Material eléctrico", 28.0, 55.0, 6, 10 ],
  [ "TUB-34", "Tubo PVC 3/4\" (tramo)", "Plomería", 35.0, 60.0, 25, 8 ],
  [ "LLA-01", "Llave de paso 1/2\"", "Plomería", 95.0, 160.0, 3, 5 ],
  [ "CAF-01", "Café de grano 1 kg", "Insumos", 210.0, 320.0, 12, 4 ],
  [ "LEC-01", "Leche entera 1 L", "Insumos", 24.0, 30.0, 2, 6 ],
  [ "REF-60", "Refresco 600 ml", "Abarrotes", 11.0, 18.0, 120, 24 ],
  [ "FOC-09", "Foco LED 9 W", "Material eléctrico", 32.0, 55.0, 0, 10 ],
  [ "HIE-05", "Hielo bolsa 5 kg", "Insumos", 25.0, 40.0, 0, 5 ]
].freeze

# Asistencia de hoy por empleado (mismo orden que PEOPLE): [tipo, hora, minuto].
# Las faltas también llevan checkin_at porque el dashboard cuenta por checkin_at de hoy.
TODAY_ATTENDANCE = [
  [ :normal, 8, 50 ],
  [ :late, 9, 20 ],
  [ :normal, 8, 55 ],
  [ :absent, 9, 0 ],
  [ :late, 9, 40 ]
].freeze

# Órdenes en modo "service" (con cliente, pasos y conceptos). Cada acción es [acción, parámetros, quién]:
# quién es :staff (el empleado asignado, que es el staff@ de la empresa) o :boss (el dueño).
# employee: 0 es el staff@; 1 es otro técnico; nil queda sin asignar.
SERVICE_ORDERS = [
  { title: "Instalación de contactos en cocina", priority: :high, employee: 0, due: 1,
    customer: [ "Café La Plaza", "5598765432", "Calle 5 de Mayo 10" ],
    steps: [ "Medir el cableado", "Instalar los contactos", "Probar el circuito" ], steps_done: 0, actions: [] },
  { title: "Cambio de centro de carga", priority: :urgent, employee: 0, due: 0,
    customer: [ "Laura Méndez", "5512345678", "Av. Juárez 120" ],
    steps: [ "Cortar la luz", "Desmontar el tablero", "Instalar el centro de carga" ], steps_done: 1,
    actions: [ [ :start, {}, :staff ] ], note: "El cliente pide terminar antes de las 5.", photo: true,
    items: [ [ "CON-02", 2 ] ] },
  { title: "Revisión de tablero principal", priority: :medium, employee: 0, due: -1,
    customer: [ "Dr. Ramón Ortiz", "5587654321", "Calle Hidalgo 45" ],
    steps: [ "Revisar interruptores", "Apretar conexiones" ], steps_done: 2, items: [ [ "APA-01", 3 ] ], labor: 450,
    actions: [ [ :start, {}, :staff ], [ :finish, {}, :staff ] ] },
  { title: "Cableado de oficina nueva", priority: :high, employee: 1, due: 3,
    customer: [ "Despacho Ríos", "5544332211", "Insurgentes 300, piso 2" ],
    steps: [ "Tender cable", "Colocar canaletas" ], steps_done: 1, items: [ [ "CAB-12", 40 ] ], labor: 900,
    actions: [ [ :start, {}, :boss ] ] },
  { title: "Cambio de luminarias en bodega", priority: :medium, employee: 0, due: -3,
    customer: [ "Bodega San José", "5533221100", "Parque Industrial, nave 4" ],
    steps: [ "Retirar las lámparas viejas", "Instalar los focos LED" ], steps_done: 2, items: [ [ "FOC-09", 8 ] ], labor: 600,
    actions: [ [ :start, {}, :staff ], [ :finish, {}, :staff ], [ :charge, { payment_method: "cash", amount_received: 2000 }, :staff ] ],
    note: "Se dejó la bodega limpia.", photo: true },
  { title: "Mantenimiento preventivo mensual", priority: :low, employee: 1, due: -5,
    customer: [ "Ferretería El Clavo", "5566778899", "Calle Morelos 8" ],
    steps: [ "Revisar tableros" ], steps_done: 1, labor: 700,
    actions: [ [ :start, {}, :boss ], [ :finish, {}, :boss ],
               [ :charge, { payment_method: "card" }, :boss ],
               [ :void_charge, { reason: "El cliente pidió factura" }, :boss ] ] },
  { title: "Cotización de remodelación", priority: :medium, employee: nil, due: 7,
    customer: [ "Familia Torres", "5599887766", "Privada Los Pinos 3" ], steps: [ "Visitar el sitio" ],
    steps_done: 0, actions: [] },
  { title: "Cambio de llave de paso", priority: :low, employee: 1, due: -2,
    customer: [ "Sra. Elena Cruz", "5511223344", "Calle Pino 12" ], steps: [], steps_done: 0,
    actions: [ [ :cancel, { reason: "El cliente lo resolvió por su cuenta" }, :boss ] ] }
].freeze

# Órdenes en modo "order": pedidos de mesa con conceptos del menú, sin pasos ni cliente.
TABLE_ORDERS = [
  { title: "Mesa 4", employee: 0, items: [ [ "CAF-01", 2 ], [ "REF-60", 2 ] ], actions: [] },
  { title: "Mesa 7", employee: 0, items: [ [ "LEC-01", 3 ], [ "HIE-05", 1 ] ],
    actions: [ [ :start, {}, :staff ] ] },
  { title: "Barra - Pedido para llevar", employee: 0, items: [ [ "CAF-01", 1 ], [ "REF-60", 3 ] ],
    actions: [ [ :start, {}, :staff ], [ :finish, {}, :staff ] ] },
  { title: "Mesa 2", employee: 0, items: [ [ "CAF-01", 1 ], [ "LEC-01", 2 ] ],
    actions: [ [ :start, {}, :staff ], [ :finish, {}, :staff ],
               [ :charge, { payment_method: "cash", amount_received: 1000 }, :staff ] ] },
  { title: "Mesa 5", employee: 1, items: [ [ "REF-60", 4 ] ],
    actions: [ [ :finish, {}, :boss ], [ :charge, { payment_method: "card" }, :boss ] ] },
  { title: "Mesa 9", employee: 1, items: [ [ "CAF-01", 2 ] ],
    actions: [ [ :finish, {}, :boss ], [ :charge, { payment_method: "transfer" }, :boss ],
               [ :void_charge, { reason: "Cobro duplicado" }, :boss ] ] },
  { title: "Mesa 1", employee: nil, items: [ [ "REF-60", 2 ] ], actions: [] },
  { title: "Mesa 3", employee: 1, items: [ [ "LEC-01", 1 ] ],
    actions: [ [ :cancel, { reason: "Los clientes se fueron" }, :boss ] ] }
].freeze

# PNG de 1x1 para la foto de demo.
DEMO_PHOTO = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==").freeze

# Crea una orden de demo y la lleva a su estado con WorkOrders::Transition, así queda con su historia.
def demo_order(company:, owner:, staff:, employees:, products:, spec:, index:, service:)
  employee = spec[:employee] && employees[spec[:employee]]
  order = WorkOrder.create!(
    company: company, created_by: owner, employee: employee, title: spec[:title],
    priority: spec[:priority] || :medium, due_date: spec[:due] && spec[:due].days.from_now,
    description: service ? "Orden de demo para #{company.name}." : nil,
    customer_name: spec.dig(:customer, 0), customer_phone: spec.dig(:customer, 1),
    customer_address: spec.dig(:customer, 2)
  )
  order.work_order_events.create!(kind: :created, actor: owner)

  position = 0
  Array(spec[:items]).each do |sku, quantity|
    product = products.find { |pr| pr.sku == sku }
    WorkOrderItem.create!(work_order: order, product: product, quantity: quantity, unit: "pza",
                          position: position)
    position += 1
  end
  if spec[:labor]
    WorkOrderItem.create!(work_order: order, description: "Mano de obra", quantity: 1, unit: "serv",
                          unit_price: spec[:labor], position: position)
  end

  Array(spec[:steps]).each_with_index do |description, i|
    step = WorkOrderStep.create!(work_order: order, description: description, position: i)
    step.mark_done!(owner) if i < spec[:steps_done].to_i
  end

  if spec[:note]
    order.work_order_events.create!(kind: :note, actor: owner, data: { "text" => spec[:note] })
  end
  if spec[:photo]
    photo = order.work_order_attachments.new(uploaded_by: owner, description: "Trabajo terminado")
    photo.file.attach(io: StringIO.new(DEMO_PHOTO), filename: "foto-demo.png", content_type: "image/png")
    photo.save!
    order.work_order_events.create!(kind: :photo, actor: owner, data: { attachment_id: photo.id })
  end

  boss_context  = WorkOrders::Transition::Context.new(user: owner, role: "owner", employee: nil)
  staff_context = WorkOrders::Transition::Context.new(user: staff, role: "staff", employee: employees[0])
  spec[:actions].each do |action, params, by|
    WorkOrders::Transition.call(order, action, by == :staff ? staff_context : boss_context, params)
  end
  order
end

def demo_user(email:, first_name:, last_name:, role:, company:)
  user = User.find_or_initialize_by(email: email)
  user.assign_attributes(first_name: first_name, last_name: last_name, phone: "5512345678", active: true)
  user.password = DEMO_PASSWORD if user.new_record?
  user.save!
  demo_membership(user, company, role)
  user
end

def demo_membership(user, company, role)
  UserCompany.find_or_initialize_by(user: user, company: company).update!(role: role)
end

DEMO_COMPANIES.each do |cfg|
  company = Company.find_or_create_by!(slug: cfg[:slug]) { |c| c.name = cfg[:name] }

  sub = company.subscription || Subscription.start_trial!(company, plan: cfg[:plan])
  plan = Plan.find(cfg[:plan])
  if cfg[:status] == :active
    sub.update!(plan: cfg[:plan], status: :active, billing_cycle: cfg[:billing_cycle],
                amount_cents: plan.amount_cents(cfg[:billing_cycle].to_s), trial_ends_at: nil,
                current_period_start: 10.days.ago,
                current_period_end: cfg[:billing_cycle] == :annual ? 355.days.from_now : 20.days.from_now)
  else
    sub.update!(plan: cfg[:plan], status: cfg[:status], amount_cents: 0,
                trial_ends_at: cfg[:trial_days_left].days.from_now)
  end

  company.update!(order_mode: cfg[:order_mode])

  next puts("  [skip] #{company.name}: ya tiene datos") if company.employees.exists?

  owner = demo_user(email: "dueno@#{cfg[:domain]}", first_name: "Dueño", last_name: company.name,
                    role: :owner, company: company)
  demo_user(email: "admin@#{cfg[:domain]}", first_name: "Admin", last_name: company.name,
            role: :admin, company: company)
  demo_user(email: "manager@#{cfg[:domain]}", first_name: "Gerente", last_name: company.name,
            role: :manager, company: company)
  staff = demo_user(email: "staff@#{cfg[:domain]}", first_name: "Ana", last_name: "López",
                    role: :staff, company: company)

  employees = PEOPLE.each_with_index.map do |(first, last, position, department), i|
    Employee.create!(company: company, name: "#{first} #{last}", position: position,
                     department: department, salary: 9_000 + (i * 1_500), status: :active,
                     phone: "55100000#{i}#{company.id % 10}",
                     user: (staff if i.zero?))
  end

  # Asistencia de los últimos 10 días hábiles.
  10.downto(1) do |days_ago|
    day = days_ago.days.ago.to_date
    next if day.sunday?

    employees.each_with_index do |employee, i|
      late = ((days_ago + i) % 5).zero?
      checkin = day.in_time_zone.change(hour: late ? 9 : 8, min: late ? 25 : 55)
      Attendance.create!(employee: employee, company: company, checkin_at: checkin,
                         checkout_at: checkin + 9.hours, attendance_type: late ? :late : :normal)
    end
  end

  # Asistencia de hoy, con retardos y faltas, sin salida registrada.
  today = Time.zone.today
  employees.zip(TODAY_ATTENDANCE).each do |employee, (type, hour, min)|
    Attendance.create!(employee: employee, company: company, attendance_type: type,
                       checkin_at: today.in_time_zone.change(hour: hour, min: min))
  end

  products = PRODUCTS.map do |sku, name, category, cost, price, stock, min_stock|
    product = Product.create!(company: company, sku: sku, name: name, category: category,
                              unit_cost: cost, price: price, stock: 0, min_stock: min_stock)
    StockMovement.create!(product: product, company: company, movement_type: :entry,
                          qty: stock + 5, note: "Inventario inicial")
    StockMovement.create!(product: product, company: company, movement_type: :exit,
                          qty: 5, note: "Venta de mostrador")
    product
  end

  next puts("  [ok] #{company.name} (#{cfg[:plan]}, sin órdenes)") unless plan.includes?(:work_orders)

  service = company.order_mode_service?
  (service ? SERVICE_ORDERS : TABLE_ORDERS).each_with_index do |spec, i|
    demo_order(company: company, owner: owner, staff: staff, employees: employees, products: products,
               spec: spec, index: i, service: service)
  end

  puts "  [ok] #{company.name} (#{cfg[:plan]}, #{cfg[:status]})"
end

# Sucursal de Sazón: usa la suscripción y los módulos de la principal (sin prueba propia).
sazon = Company.find_by!(slug: "restaurante-sazon")
centro = Company.find_or_create_by!(slug: "restaurante-sazon-centro") do |c|
  c.name = "Restaurante Sazón Centro"
  c.parent = sazon
  c.order_mode = sazon.order_mode
end
demo_membership(User.find_by!(email: "dueno@sazon.demo"), centro, :owner)
demo_user(email: "admin@centro.sazon.demo", first_name: "Admin", last_name: centro.name, role: :admin, company: centro)
unless centro.employees.exists?
  PEOPLE.first(2).each_with_index do |(first, last, position, department), i|
    Employee.create!(company: centro, name: "#{first} #{last}", position: position, department: department,
                     salary: 9_500 + (i * 1_000), status: :active, phone: "55200000#{i}#{centro.id % 10}")
  end
end
puts "  [ok] #{centro.name} (sucursal de #{sazon.name})"

# Una persona con roles distintos en dos empresas.
multi = demo_user(email: "multi@demo.demo", first_name: "Paula", last_name: "Multiempresa",
                  role: :owner, company: Company.find_by!(slug: "electricidad-volta"))
demo_membership(multi, sazon, :staff)
puts "  [ok] multi@demo.demo: owner de Electricidad Volta y staff de Restaurante Sazón"

# Restaurante (spec 013): estaciones, mesas y menú de Sazón. Se puede volver a ejecutar sin duplicar.
cocina = sazon.stations.find_or_create_by!(name: "Cocina") { |st| st.position = 1 }
barra = sazon.stations.find_or_create_by!(name: "Barra") { |st| st.position = 2 }
(1..6).each { |n| sazon.dining_tables.find_or_create_by!(name: n.to_s) { |t| t.position = n } }
[
  [ "SZN-TAC", "Tacos al pastor", "Platillos", 25.0, 70.0, cocina, true, 40, 10 ],
  [ "SZN-ENS", "Ensalada de la casa", "Platillos", 22.0, 85.0, cocina, true, 25, 5 ],
  [ "SZN-SOP", "Sopa del día", "Platillos", 15.0, 55.0, cocina, false, 0, 0 ],
  [ "SZN-POS", "Pastel de chocolate", "Postres", 20.0, 65.0, cocina, true, 12, 4 ],
  [ "SZN-AGU", "Agua de horchata", "Bebidas", 6.0, 25.0, barra, false, 0, 0 ],
  [ "SZN-CER", "Cerveza artesanal", "Bebidas", 18.0, 60.0, barra, true, 48, 12 ],
  [ "SZN-COL", "Refresco de cola", "Bebidas", 8.0, 30.0, barra, true, 5, 3 ]
].each do |sku, name, category, cost, price, station, tracked, stock, min_stock|
  product = sazon.products.find_or_initialize_by(sku: sku)
  next unless product.new_record?

  product.assign_attributes(name: name, category: category, unit_cost: cost, price: price, station: station,
                            tracks_stock: tracked, stock: 0, min_stock: min_stock)
  product.save!
  next unless stock.positive?

  StockMovement.create!(product: product, company: sazon, movement_type: :entry, qty: stock, note: "Inventario inicial")
end
puts "  [ok] #{sazon.name}: estaciones Cocina y Barra, 6 mesas y menú de restaurante"

# Menú del servicio (spec 032): los insumos no se venden y el abarrote y el material eléctrico que comparte el
# catálogo de demo no salen en Tomar pedido, aunque siguen en Inventario.
insumo = sazon.product_types.find_by!(kind: "supply")
otros = sazon.product_types.find_or_create_by!(name: "Abarrotes y material") do |type|
  type.assign_attributes(kind: nil, sellable: true, in_menu: false, counted: true, fractional: false, default_unit_key: "pza", position: 4)
end
sazon.products.where(category: "Insumos").find_each { |product| product.update!(product_type: insumo) }
sazon.products.where(category: [ "Abarrotes", "Material eléctrico", "Plomería" ]).find_each { |product| product.update!(product_type: otros) }
puts "  [ok] #{sazon.name}: insumos fuera de la venta y abarrotes y material fuera del menú"

# Iconos de producto (spec 026) en algunos productos de demo; el resto usa el icono sugerido de su tipo.
{
  "SZN-TAC" => "taco", "SZN-ENS" => "salad", "SZN-SOP" => "soup", "SZN-POS" => "cake", "SZN-AGU" => "juice",
  "SZN-CER" => "beer", "SZN-COL" => "soda", "CAB-12" => "cable", "APA-01" => "bolt", "CON-02" => "plug",
  "TUB-34" => "pipe", "LLA-01" => "faucet", "FOC-09" => "bulb", "CAF-01" => "coffee", "REF-60" => "soda"
}.each do |sku, icon|
  Product.where(sku: sku, icon: nil).update_all(icon: icon)
end
puts "  [ok] iconos de producto de demo"

# Terminales de cobro (spec 015): el operador elige en cuál se pasó la tarjeta.
aroma = Company.find_by!(slug: "cafe-aroma")
[ [ aroma, "BBVA caja 1", "bbva" ], [ aroma, "Point barra", "mercado_pago" ], [ sazon, "Clip mesas", "clip" ] ].each do |company, name, provider|
  company.payment_terminals.find_or_create_by!(name: name) { |terminal| terminal.provider = provider }
end
puts "  [ok] Terminales: BBVA caja 1 y Point barra en #{aroma.name}, Clip mesas en #{sazon.name}"

puts "  Usuarios de demo: dueno@, admin@, manager@ y staff@ <dominio>.demo · contraseña #{DEMO_PASSWORD}"
