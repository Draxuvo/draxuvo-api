# Datos de demo para navegar el panel en desarrollo. Idempotente: una empresa que ya tiene
# empleados no se vuelve a llenar. Se carga desde db/seeds.rb solo en development.
# Para regenerarlos (por ejemplo, para que la asistencia de "hoy" sea de hoy): bin/rails db:reset
#
# Contraseña de todos los usuarios de demo: Demo12345*
# El rol es por empresa (user_companies.role). multi@demo.demo es owner de Volta y staff de Sazón,
# y Sazón (plan Empresa) tiene la sucursal "Restaurante Sazón Centro".

DEMO_PASSWORD = "Demo12345*".freeze

DEMO_COMPANIES = [
  { name: "Abarrotes Don Chuy", slug: "abarrotes-don-chuy", domain: "donchuy.demo",
    plan: :basic, status: :active, billing_cycle: :monthly },
  { name: "Electricidad Volta", slug: "electricidad-volta", domain: "volta.demo",
    plan: :pro, status: :active, billing_cycle: :monthly },
  { name: "Restaurante Sazón", slug: "restaurante-sazon", domain: "sazon.demo",
    plan: :enterprise, status: :active, billing_cycle: :annual },
  { name: "Café Aroma", slug: "cafe-aroma", domain: "aroma.demo",
    plan: :pro, status: :trialing, trial_days_left: 10 },
  { name: "Plomería Rápida", slug: "plomeria-rapida", domain: "plomeria.demo",
    plan: :pro, status: :expired, trial_days_left: -3 }
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

WORK_ORDERS = [
  [ "Instalación de contactos en cocina", :completed, :high, true ],
  [ "Revisión de tablero principal", :completed, :medium, false ],
  [ "Cambio de luminarias en bodega", :in_review, :medium, false ],
  [ "Reparación de fuga en baño", :in_progress, :urgent, false ],
  [ "Cableado de oficina nueva", :in_progress, :high, false ],
  [ "Mantenimiento preventivo mensual", :pending, :low, false ],
  [ "Cotización de remodelación", :pending, :medium, false ],
  [ "Cambio de llave de paso", :cancelled, :low, false ]
].freeze

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

  WORK_ORDERS.each_with_index do |(title, status, priority, paid), i|
    order = WorkOrder.create!(company: company, created_by: owner, employee: employees[i % 3 + 1],
                              title: title, priority: priority, status: :pending,
                              description: "Orden de demo para #{company.name}.",
                              due_date: (i - 2).days.from_now)
    done = %i[completed in_review].include?(status)
    products.sample(2, random: Random.new(i)).each_with_index do |product, position|
      WorkOrderItem.create!(work_order: order, product: product, quantity: position + 1,
                            unit: "pza", position: position, status: done ? :completed : :pending)
    end
    WorkOrderItem.create!(work_order: order, description: "Mano de obra", quantity: 1,
                          unit: "serv", unit_price: 450, position: 2,
                          status: done ? :completed : :pending)
    order.update!(status: status, completed_at: (status == :completed ? (i + 1).days.ago : nil))
    order.reload.ticket&.update!(status: :paid, paid_at: i.days.ago) if paid
  end

  puts "  [ok] #{company.name} (#{cfg[:plan]}, #{cfg[:status]})"
end

# Sucursal de Sazón: usa la suscripción y los módulos de la principal (sin prueba propia).
sazon = Company.find_by!(slug: "restaurante-sazon")
centro = Company.find_or_create_by!(slug: "restaurante-sazon-centro") do |c|
  c.name = "Restaurante Sazón Centro"
  c.parent = sazon
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

puts "  Usuarios de demo: dueno@, admin@, manager@ y staff@ <dominio>.demo · contraseña #{DEMO_PASSWORD}"
