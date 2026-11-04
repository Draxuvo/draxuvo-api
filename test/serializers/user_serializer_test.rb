require "test_helper"

# Spec 054: cada empresa de la sesión trae sus módulos activos.
class UserSerializerTest < ActiveSupport::TestCase
  def modules_of(user, company) = UserSerializer.new(user).as_json[:companies].find { |c| c[:id] == company.id }[:modules]

  test "lists the active modules of the plan of each company" do
    modules = modules_of(users(:pro_co_owner), companies(:pro_co))
    assert_equal Plan.find(:pro).modules.map(&:to_s).sort, modules.sort
    assert_not_includes modules, "pos"
    assert_not_includes modules, "whatsapp"
  end

  test "includes a contracted extra" do
    owner = users(:pos_admin)
    modules = modules_of(owner, companies(:pos_co))
    assert_includes modules, "pos"
    assert_includes modules, "inventory"
  end

  test "leaves out a module the super admin turned off" do
    company = companies(:pro_co)
    company.update!(disabled_modules: %w[terminals])
    modules = modules_of(users(:pro_co_owner), company.reload)
    assert_not_includes modules, "terminals"
    assert_includes modules, "inventory"
  end

  test "an extra that was cancelled and already ended is not listed" do
    company = companies(:pos_co)
    company.subscription.addons.update_all(ends_at: 1.day.ago)
    assert_not_includes modules_of(users(:pos_admin), company.reload), "pos"
  end

  test "a company without an active plan access still answers a list, never nil" do
    assert_kind_of Array, modules_of(users(:expired_staff), companies(:expired_co))
  end
end
