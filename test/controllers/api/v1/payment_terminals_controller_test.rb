require "test_helper"

# Contrato: specs/015-operador-ordenes-cobro-mixto/contracts/api.md (Terminales).
class Api::V1::PaymentTerminalsControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/payment_terminals".freeze

  setup do
    @company = companies(:pro_co)
    @admin = auth_headers(users(:pro_co_owner), @company)
  end

  test "staff and managers list only active terminals and cannot write" do
    [ users(:pro_staff), users(:pro_manager) ].each do |user|
      headers = auth_headers(user, @company)
      get BASE, params: { include_inactive: true }, headers: headers
      assert_response :ok
      assert_equal [ "BBVA caja 1" ], response.parsed_body["results"].map { |t| t["name"] }
      assert_nil response.parsed_body["results"].first["payments_count"]

      post BASE, params: { payment_terminal: { name: "Nueva", provider: "clip" } }, headers: headers, as: :json
      assert_response :forbidden
      patch "#{BASE}/#{payment_terminals(:pro_bbva).id}", params: { payment_terminal: { active: false } }, headers: headers, as: :json
      assert_response :forbidden
      delete "#{BASE}/#{payment_terminals(:pro_clip_off).id}", headers: headers
      assert_response :forbidden
    end
  end

  test "admin creates, edits, deactivates and lists inactive terminals" do
    post BASE, params: { payment_terminal: { name: "Point barra", provider: "mercado_pago" } }, headers: @admin, as: :json
    assert_response :created
    created = response.parsed_body
    assert_equal({ "name" => "Point barra", "provider" => "mercado_pago", "provider_label" => "Mercado Pago", "active" => true,
                   "payments_count" => 0 }, created.except("id"))

    patch "#{BASE}/#{created['id']}", params: { payment_terminal: { active: false } }, headers: @admin, as: :json
    assert_response :ok
    assert_equal false, response.parsed_body["active"]

    get BASE, params: { include_inactive: true }, headers: @admin
    assert_equal [ "BBVA caja 1", "Clip vieja", "Point barra" ], response.parsed_body["results"].map { |t| t["name"] }
    get BASE, headers: @admin
    assert_equal [ "BBVA caja 1" ], response.parsed_body["results"].map { |t| t["name"] }
  end

  test "a repeated name or an unknown provider is rejected" do
    post BASE, params: { payment_terminal: { name: "bbva CAJA 1", provider: "bbva" } }, headers: @admin, as: :json
    assert_response :unprocessable_entity
    post BASE, params: { payment_terminal: { name: "PayPal", provider: "paypal" } }, headers: @admin, as: :json
    assert_response :unprocessable_entity
  end

  test "a terminal with payments cannot be deleted, one without payments can" do
    delete "#{BASE}/#{payment_terminals(:pro_bbva).id}", headers: @admin
    assert_response :unprocessable_entity
    assert_equal "terminal_in_use", response.parsed_body.dig("error", "details", "code")
    assert PaymentTerminal.exists?(payment_terminals(:pro_bbva).id)

    delete "#{BASE}/#{payment_terminals(:pro_clip_off).id}", headers: @admin
    assert_response :ok
    assert_not PaymentTerminal.exists?(payment_terminals(:pro_clip_off).id)
  end

  test "terminals of another company are not reachable" do
    patch "#{BASE}/#{payment_terminals(:resto_point).id}", params: { payment_terminal: { name: "Mía" } }, headers: @admin, as: :json
    assert_response :not_found
    delete "#{BASE}/#{payment_terminals(:resto_point).id}", headers: @admin
    assert_response :not_found
  end

  # --- spec 030: Terminales es un módulo de Pro y Empresa ---

  test "a basic company gets 403 module_not_in_plan on every terminal route and nothing changes" do
    headers = auth_headers(users(:basic_co_owner), companies(:basic_co))
    terminal = payment_terminals(:pro_bbva)

    assert_no_difference -> { PaymentTerminal.count } do
      get BASE, headers: headers
      assert_module_blocked
      post BASE, params: { payment_terminal: { name: "Nueva", provider: "clip" } }, headers: headers, as: :json
      assert_module_blocked
      patch "#{BASE}/#{terminal.id}", params: { payment_terminal: { active: false } }, headers: headers, as: :json
      assert_module_blocked
      delete "#{BASE}/#{terminal.id}", headers: headers
      assert_module_blocked
    end
    assert terminal.reload.active?
  end

  test "a pro company with the module turned off by the super admin is blocked, even for the cashier" do
    @company.update!(disabled_modules: %w[terminals])

    [ @admin, auth_headers(users(:pro_staff), @company) ].each do |headers|
      get BASE, headers: headers
      assert_module_blocked
    end
  end

  test "the super admin keeps the gate bypass like with every module" do
    @company.update!(disabled_modules: %w[terminals])

    get BASE, headers: auth_headers(users(:super_admin), @company)

    assert_response :ok
  end

  test "turning the module off and on again keeps the terminals" do
    @company.update!(disabled_modules: %w[terminals])
    @company.update!(disabled_modules: [])

    get BASE, params: { include_inactive: true }, headers: @admin

    assert_response :ok
    assert_includes response.parsed_body["results"].map { |t| t["name"] }, "BBVA caja 1"
  end

  private

  def assert_module_blocked
    assert_response :forbidden
    details = response.parsed_body.dig("error", "details")
    assert_equal "module_not_in_plan", details["code"]
    assert_equal "terminals", details["module"]
  end
end
