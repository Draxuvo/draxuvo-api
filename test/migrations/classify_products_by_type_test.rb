require "test_helper"
require Rails.root.join("db/migrate/20261021100200_classify_products_by_type")

# La clasificación de productos existentes (spec 016, US5, research R6) sobre datos sin tipo.
class ClassifyProductsByTypeTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  test "existing products land in the initial types of their company by how they are used" do
    company = Company.create!(name: "Mariscos Viejos", order_mode: :order)
    company.product_types.delete_all
    conn = ActiveRecord::Base.connection
    conn.change_column_null :products, :product_type_id, true
    insert = ->(sku, tracks, available) do
      conn.execute("INSERT INTO products (company_id, sku, name, stock, tracks_stock, available, created_at, updated_at) " \
                   "VALUES (#{company.id}, '#{sku}', '#{sku}', 0, #{tracks}, #{available}, NOW(), NOW())")
    end
    insert.("BEER", true, true)
    insert.("LIME", false, false)
    insert.("TACO", false, true)
    Product.where.not(company_id: company.id).where(product_type_id: nil).update_all(product_type_id: product_types(:one_sold).id)

    ActiveRecord::Migration.suppress_messages { ClassifyProductsByType.new.up }

    kinds = company.products.joins(:product_type).pluck(:sku, "product_types.kind", :available, :tracks_stock).to_h { |sku, *rest| [ sku, rest ] }
    assert_equal [ "counted_sold", true, true ], kinds["BEER"]
    assert_equal [ "supply", true, true ], kinds["LIME"]
    assert_equal [ "sold", true, false ], kinds["TACO"]
    assert_equal %w[Platillo Bebida Insumo], company.product_types.order(:position).pluck(:name)
  end
end
