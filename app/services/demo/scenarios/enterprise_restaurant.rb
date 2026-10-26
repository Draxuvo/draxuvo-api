# Plan Empresa: el restaurante del plan Pro más una sucursal, con el dueño miembro de las dos (todos los módulos).
module Demo
  module Scenarios
    class EnterpriseRestaurant < ProRestaurant
      COMPANY_NAME = "Grupo Sazón (demo)".freeze
      BRANCH_NAME = "Sazón Centro (demo)".freeze

      def build
        super
        build_branch
      end

      private

      def build_branch
        stations, tables = setup_restaurant(branch, tables: 4)
        menu = create_menu(branch, stations)
        waiter = create_staff_user(branch, "Mónica", "Meseros", position: "Mesera", department: "Salón", salary: 8_200)
        employees = branch.employees.order(:id).to_a + create_employees(branch, people: RestaurantSupport::PEOPLE, count: 2)
        fill_attendance(employees, branch)
        paid = open_check(branch, waiter, [ [ menu["TAC"], 2, nil ], [ menu["CER"], 1, nil ] ], table: tables[0], minutes: 50)
        pay(paid, waiter, [ [ "cash", 200, 200 ] ])
        open_check(branch, waiter, [ [ menu["HAM"], 1, nil ], [ menu["LIM"], 2, nil ] ], table: tables[1], minutes: 20, state: :delivered)
        open_check(branch, waiter, [ [ menu["QUE"], 2, nil ] ], table: tables[2], minutes: 8, state: :preparing)
        adjust_stock(menu["CER"], 5)
      end
    end
  end
end
