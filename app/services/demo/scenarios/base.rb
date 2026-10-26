# Base de los escenarios de la demo (spec 039). Cada escenario hereda de aquí e implementa `build`.
#
# Reglas de todos los escenarios:
# - Deterministas: mismos nombres, cifras y orden en cada visita. Solo las fechas son relativas a hoy, para que
#   Asistencia, Reportes y Cuentas siempre se vean vivos.
# - Ficticios: nada viene de una empresa real.
# - Sin efectos externos: no mandan correos, mensajes ni cobros; solo escriben en la base de la propia demo.
module Demo
  module Scenarios
    class Base
      attr_reader :company, :owner, :branch

      PEOPLE = [
        [ "Ana López", "Encargada", "Operación", 9_000 ],
        [ "Luis Martínez", "Técnico", "Campo", 10_500 ],
        [ "María Hernández", "Cajera", "Ventas", 12_000 ],
        [ "Jorge García", "Ayudante", "Campo", 13_500 ],
        [ "Sofía Ramírez", "Almacenista", "Almacén", 15_000 ]
      ].freeze

      # Asistencia de hoy por persona (mismo orden que PEOPLE): [tipo, hora, minuto].
      TODAY_ATTENDANCE = [ [ :normal, 8, 50 ], [ :late, 9, 20 ], [ :normal, 8, 55 ], [ :late, 9, 40 ] ].freeze

      def self.call(**kwargs) = new(**kwargs).tap(&:build)

      def initialize(company:, owner:, branch: nil)
        @company = company
        @owner = owner
        @branch = branch
      end

      def build = raise(NotImplementedError, "#{self.class} debe implementar build")

      private

      def today = Time.zone.today

      # Personas con ficha de empleado, activas y con salario.
      def create_employees(target = company, people: PEOPLE, count: people.size)
        people.first(count).each_with_index.map do |(name, position, department, salary), i|
          Employee.create!(company: target, name: name, position: position, department: department, salary: salary,
                           status: :active, phone: format("551000%02d%02d", target.id % 100, i))
        end
      end

      # Usuario de personal (rol staff) de la demo: su membresía crea la ficha de empleado, que aquí se completa.
      def create_staff_user(target, first_name, last_name, position:, department:, salary:)
        user = User.create!(first_name: first_name, last_name: last_name, active: true, phone: "5500000000",
                            email: "demo-#{SecureRandom.hex(8)}@#{Demo::Provision::EMAIL_DOMAIN}",
                            password: "#{SecureRandom.base64(24)}aA1!")
        UserCompany.create!(user: user, company: target, role: :staff)
        target.employees.find_by!(user: user).update!(position: position, department: department, salary: salary,
                                                      phone: format("551000%02d%02d", target.id % 100, user.id % 100))
        user
      end

      # Deja el producto con esa existencia con una salida de merma (para que haya alertas de stock bajo y agotado).
      def adjust_stock(product, target_stock)
        product.reload
        diff = product.stock.to_i - target_stock
        return unless diff.positive?

        StockMovement.create!(product: product, company: product.company, movement_type: :exit, qty: diff,
                              note: "Merma", user: owner)
      end

      # 10 días hábiles de entradas y salidas, con un retardo cada cierto tiempo, y las entradas de hoy.
      def fill_attendance(employees, target = company)
        10.downto(1) do |days_ago|
          day = days_ago.days.ago.to_date
          next if day.sunday?

          employees.each_with_index do |employee, i|
            late = ((days_ago + i) % 5).zero?
            checkin = day.in_time_zone.change(hour: late ? 9 : 8, min: late ? 25 : 55)
            Attendance.create!(employee: employee, company: target, checkin_at: checkin, checkout_at: checkin + 9.hours,
                               attendance_type: late ? :late : :normal)
          end
        end
        employees.zip(TODAY_ATTENDANCE).each do |employee, (type, hour, min)|
          next unless type

          Attendance.create!(employee: employee, company: target, attendance_type: type,
                             checkin_at: today.in_time_zone.change(hour: hour, min: min))
        end
      end

      # Producto con su inventario inicial: una entrada y una salida, para que el historial cuadre con la existencia.
      # row: [sku, nombre, categoría, costo, precio, existencia, mínimo]
      def create_product(row, target: company, **attrs)
        sku, name, category, cost, price, stock, min_stock = row
        product = Product.create!(company: target, sku: sku, name: name, category: category, unit_cost: cost,
                                  price: price, stock: 0, min_stock: min_stock, **attrs)
        return product unless stock.positive?

        StockMovement.create!(product: product, company: target, movement_type: :entry, qty: stock + 5,
                              note: "Inventario inicial", user: owner)
        StockMovement.create!(product: product, company: target, movement_type: :exit, qty: 5,
                              note: "Venta de mostrador", user: owner)
        product
      end

      # Corrida mensual del mes pasado, aprobada y pagada, para ver historial, recibos y Reportes → Nómina.
      def pay_last_month_payroll(target = company)
        last_month = Date.current.prev_month
        run = Payroll::BuildRun.call(company: target, user: owner, period_type: :monthly,
                                     starts_on: last_month.beginning_of_month, ends_on: last_month.end_of_month)
        run = Payroll::Approve.call(run: run, user: owner, lock_version: run.lock_version)
        Payroll::Pay.call(run: run, user: owner, payment_method: "transfer",
                          paid_on: [ last_month.end_of_month + 1, today ].min, reference: "Demo")
      end
    end
  end
end
