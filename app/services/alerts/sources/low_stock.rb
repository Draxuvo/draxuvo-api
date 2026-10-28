module Alerts
  module Sources
    # Productos con stock bajo (spec 045): la misma regla del inventario y los reportes (`Product.low_stock`).
    # No tiene tiempo ni se pospone; es crítica cuando ya no queda nada.
    class LowStock < Base
      KIND = "low_stock".freeze

      def self.module_key = :inventory

      def call
        Product.where(company_id: company.id).low_stock.order(:name).map do |product|
          Alert.new(
            kind: KIND, subject_key: "product:#{product.id}", severity: product.stock.to_d <= 0 ? "critical" : "warning",
            subject: { type: "product", id: product.id, label: product.name },
            stock: Product.quantity(product.stock), min_stock: Product.quantity(product.min_stock)
          )
        end
      end
    end
  end
end
