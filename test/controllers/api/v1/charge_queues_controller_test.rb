require "test_helper"

# Spec 058 (US3, FR-020): cuántas cosas esperan el cobro de un jefe. contracts/api.md.
class Api::V1::ChargeQueuesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/charge_queue".freeze

  def json = response.parsed_body

  test "only bosses read it" do
    get PATH, headers: auth_headers(users(:pos_staff), companies(:pos_co))
    assert_response :forbidden
  end

  test "with the option off everything is zero" do
    sale = open_sale(users(:pos_staff), [ products(:pos_cuaderno), 1 ])
    sale.update_columns(submitted_at: Time.current)

    get PATH, headers: auth_headers(users(:pos_admin), companies(:pos_co))
    assert_response :ok
    assert_equal({ "enabled" => false, "sales" => 0, "work_orders" => 0, "checks" => 0, "total" => 0 }, json)
  end

  test "counts sales ready to charge, not the ones in capture" do
    company = companies(:pos_co)
    company.update!(boss_only_charge: true)
    open_sale(users(:pos_staff), [ products(:pos_cuaderno), 1 ]).update_columns(submitted_at: Time.current)
    open_sale(users(:pos_staff2), [ products(:pos_cuaderno), 1 ])

    get PATH, headers: auth_headers(users(:pos_owner), company)
    assert_equal true, json["enabled"]
    assert_equal 1, json["sales"]
    assert_equal 0, json["work_orders"], "pos_co has no work orders module"
    assert_equal 1, json["total"]
  end

  test "counts done work orders" do
    company = companies(:pro_co)
    company.update!(boss_only_charge: true)

    get PATH, headers: auth_headers(users(:pro_co_owner), company)
    assert_equal company.work_orders.where(status: :done).count, json["work_orders"]
    assert_operator json["work_orders"], :>=, 1
    assert_equal 0, json["sales"], "pro_co has no pos module"
  end

  test "counts open checks with a charge request" do
    company = companies(:resto_co)
    company.update!(boss_only_charge: true)
    checks(:open_check).update_columns(charge_requested_at: Time.current)

    get PATH, headers: auth_headers(users(:resto_owner), company)
    assert_equal 1, json["checks"]
  end

  test "is isolated per company" do
    companies(:resto_co).update!(boss_only_charge: true)
    checks(:open_check).update_columns(charge_requested_at: Time.current)
    companies(:pos_co).update!(boss_only_charge: true)

    get PATH, headers: auth_headers(users(:pos_owner), companies(:pos_co))
    assert_equal 0, json["checks"]
  end
end
