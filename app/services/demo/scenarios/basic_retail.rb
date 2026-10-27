# Plan Básico: abarrotes pequeños (empleados, asistencia, inventario y reportes; sin órdenes ni restaurante).
module Demo
  module Scenarios
    class BasicRetail < Base
      COMPANY_NAME = "Abarrotes La Esquina (demo)".freeze
      ORDER_MODE = :service

      PRODUCTS = [
        [ "ABA-001", "Refresco de cola 600 ml", "Bebidas", 11, 18, 120, 24 ],
        [ "ABA-002", "Agua purificada 1 L", "Bebidas", 7, 12, 90, 20 ],
        [ "ABA-003", "Leche entera 1 L", "Lácteos", 24, 30, 2, 6 ],
        [ "ABA-004", "Huevo (kg)", "Abarrotes", 38, 52, 0, 5 ],
        [ "ABA-005", "Pan de caja", "Panadería", 32, 45, 14, 6 ],
        [ "ABA-006", "Arroz 1 kg", "Abarrotes", 22, 32, 40, 10 ],
        [ "ABA-007", "Frijol negro 1 kg", "Abarrotes", 28, 40, 35, 10 ],
        [ "ABA-008", "Aceite vegetal 900 ml", "Abarrotes", 36, 52, 3, 8 ],
        [ "ABA-009", "Azúcar 1 kg", "Abarrotes", 24, 34, 50, 12 ],
        [ "ABA-010", "Atún en lata", "Enlatados", 17, 26, 60, 15 ],
        [ "ABA-011", "Galletas surtidas", "Botanas", 14, 22, 45, 12 ],
        [ "ABA-012", "Papel higiénico 4 rollos", "Limpieza", 28, 42, 25, 8 ],
        [ "ABA-013", "Detergente en polvo 1 kg", "Limpieza", 33, 48, 18, 6 ],
        [ "ABA-014", "Jabón de barra", "Limpieza", 9, 15, 70, 15 ]
      ].freeze

      # Los tipos iniciales del giro «servicio» (Refacción, Material) no tienen sentido en una tienda de abarrotes.
      TYPE_NAMES = { "sold" => "Servicio", "counted_sold" => "Mercancía", "supply" => "Insumo" }.freeze

      def build
        rename_product_types
        employees = create_employees
        fill_attendance(employees)
        PRODUCTS.each { |row| create_product(row) }
        pay_last_month_payroll
      end

      private

      def rename_product_types
        TYPE_NAMES.each { |kind, name| company.product_types.find_by!(kind: kind).update!(name: name) }
      end
    end
  end
end
