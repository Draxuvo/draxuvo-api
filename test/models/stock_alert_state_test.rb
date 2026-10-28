require "test_helper"

class StockAlertStateTest < ActiveSupport::TestCase
  test "a product has at most one state and pending/notified split by notified_at" do
    company = companies(:resto_co)
    product = products(:resto_tacos)
    state = StockAlertState.create!(company: company, product: product, detected_at: Time.current)

    assert_includes StockAlertState.pending, state
    state.update!(notified_at: Time.current)
    assert_includes StockAlertState.notified, state
    assert_not_includes StockAlertState.pending, state

    assert_not StockAlertState.new(company: company, product: product, detected_at: Time.current).valid?
  end

  test "deleting the product deletes its state" do
    product = Product.create!(company: companies(:one), name: "Borrable", sku: "BOR-1", category: "Otro")
    StockAlertState.create!(company: product.company, product: product, detected_at: Time.current)
    Product.where(id: product.id).delete_all
    assert_equal 0, StockAlertState.where(product_id: product.id).count
  end
end
