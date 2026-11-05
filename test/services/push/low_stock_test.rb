require "test_helper"

class Push::LowStockTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
    register_device(@owner)
    register_device(users(:resto_waiter))
  end

  def products(*names) = names.map { |name| Product.new(name: name) }

  test "sends one grouped notice to bosses with count and up to three names" do
    fake = with_fake_expo { Push::LowStock.call(company: @company, products: products("Coca 600", "Limón", "Hielo", "Sal")) }

    assert_equal 1, fake.messages.size, "el mesero no recibe stock bajo"
    assert_equal "Restaurante Prueba · Stock bajo", fake.messages.first[:title]
    assert_equal "4 productos bajo el mínimo: Coca 600, Limón, Hielo…", fake.messages.first[:body]
    assert_equal "/alertas", fake.messages.first.dig(:data, :path)
  end

  test "respects the push preference independently from the email one" do
    NotificationPreference.for(@owner, @company).update!(push_low_stock: false, stock_email: true)
    fake = with_fake_expo { Push::LowStock.call(company: @company, products: products("Coca 600")) }
    assert_empty fake.messages
    assert_equal "skipped_preference", PushDelivery.last.status
  end

  test "an Expo failure is logged as failed without raising" do
    Push::ExpoClient.stub(:new, PushHelpers::FakeExpo.new(raise_error: Push::ExpoClient::Transient.new("expo_http_503"))) do
      Push::LowStock.call(company: @company, products: products("Coca 600"))
    end
    assert_equal "failed", PushDelivery.last.status
  end
end
