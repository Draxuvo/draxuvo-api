# Plan Pro, restaurante: estaciones Cocina y Barra, 8 mesas, un menú con tipos y cuentas en cada estado (ocupada,
# por cobrar y cobrada hoy con su ticket), más existencias bajas y agotadas.
module Demo
  module Scenarios
    class ProRestaurant < Base
      include RestaurantSupport

      COMPANY_NAME = "Restaurante Sazón (demo)".freeze
      ORDER_MODE = :order

      def build
        stations, tables = setup_restaurant(company, tables: 8)
        menu = create_menu(company, stations)
        carlos = create_staff_user(company, "Carlos", "Mesero", position: "Mesero", department: "Salón", salary: 8_000)
        lucia = create_staff_user(company, "Lucía", "Mesera", position: "Mesero", department: "Salón", salary: 8_500)
        employees = company.employees.order(:id).to_a + create_employees(people: RestaurantSupport::PEOPLE)
        fill_attendance(employees)
        build_checks(menu, tables, carlos, lucia)
        adjust_stock(menu["CER"], 4)
        adjust_stock(menu["COL"], 0)
        pay_last_month_payroll
      end

      private

      def build_checks(menu, tables, carlos, lucia)
        # Cobradas hoy (con ticket): una mixta y una en efectivo.
        mixed = open_check(company, lucia, [ [ menu["TAC"], 2, "sin cebolla" ], [ menu["HAM"], 1, nil ], [ menu["CER"], 2, nil ] ],
                           table: tables[2], minutes: 95)
        pay(mixed, lucia, [ [ "cash", 200, 500 ], [ "card", 180, "A8812" ] ])
        cash = open_check(company, carlos, [ [ menu["ENC"], 2, nil ], [ menu["LIM"], 2, nil ] ], table: tables[5], minutes: 70)
        pay(cash, carlos, [ [ "cash", 246, 300 ] ])
        # Por cobrar: todo entregado y con saldo.
        open_check(company, carlos, [ [ menu["HAM"], 2, "sin jitomate" ], [ menu["ENS"], 1, nil ], [ menu["COL"], 3, nil ] ],
                   table: tables[1], minutes: 40, state: :delivered)
        # Ocupadas: una en preparación, una lista para entregar y un pedido para llevar.
        open_check(company, carlos, [ [ menu["TAC"], 3, nil ], [ menu["CER"], 2, nil ] ], table: tables[0], minutes: 12, state: :preparing)
        open_check(company, lucia, [ [ menu["QUE"], 2, nil ], [ menu["PAS"], 1, nil ] ], table: tables[3], minutes: 25, state: :ready)
        open_check(company, carlos, [ [ menu["SOP"], 2, nil ], [ menu["HOR"], 2, nil ] ], takeout: "Mario", minutes: 6, state: :sent)
      end
    end
  end
end
