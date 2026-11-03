require "test_helper"

# Spec 053: el extra lo enciende y apaga solo el super admin, con `X-Company-Id` de la empresa (como los módulos, spec 017).
class Api::V1::SubscriptionAddonsControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/subscription".freeze

  setup do
    @company = companies(:basic_co)
    @subscription = subscriptions(:basic_co)
    @owner = users(:basic_co_owner)
    @super = users(:super_admin)
    @headers = auth_headers(@super, @company)
    @created = []
    @deleted = []
    @mails = []
  end

  def json = response.parsed_body

  def code = json.dig("error", "details", "code")

  def call(verb, path, params: {}, headers: @headers, **stubs)
    ResendMailer.stub(:addon_changed, ->(**kw) { @mails << kw }) do
      with_memory_cache do
        with_addon_stubs(created: @created, deleted: @deleted, **stubs) { public_send(verb, "#{BASE}#{path}", params: params, headers: headers, as: :json) }
      end
    end
  end

  # --- quién puede ---

  test "owner, administrator and staff get 403 on turning the add-on on, off or back on" do
    admin = create_member(@company, role: :admin)
    staff = create_member(@company, role: :staff)
    grant_addon!(@company, :pos)
    [ @owner, admin, staff ].each do |user|
      call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(user, @company))
      assert_response :forbidden
      call(:delete, "/addons/pos", headers: auth_headers(user, @company))
      assert_response :forbidden
      call(:post, "/addons/pos/reactivate", headers: auth_headers(user, @company))
      assert_response :forbidden
    end
    assert_empty @created
    assert_empty @deleted
    assert @company.reload.module_active?(:pos)
  end

  test "requires authentication" do
    post "#{BASE}/addons", params: { module: "pos" }, as: :json
    assert_response :unauthorized
  end

  # --- encender (suscripción pagada) ---

  test "the super admin turns it on: prorated charge, breakdown, history with prices and a notice" do
    call(:post, "/addons", params: { module: "pos" })

    assert_response :created
    assert_equal 39_900, json["amount_cents"]
    assert_equal 19_900, json["addons_cents"]
    assert_equal [ "pos" ], json["addons"].map { |a| a["module"] }
    assert_equal "active", json["addons"].first["status"]
    assert_includes json["active_modules"], "pos"
    assert_equal 69_368, json["total_cents"]
    assert_equal 1, @created.size

    change = @company.module_changes.order(:id).last
    assert_equal [ "pos", true, @super.id, 0, 19_900 ], [ change.module, change.enabled, change.actor_id, change.amount_before_cents, change.amount_after_cents ]
    assert_equal 1, @mails.size
    assert_equal [ "on", 69_368 ], [ @mails.first[:action], @mails.first[:total_cents] ]
  end

  test "turning it on removes it from the disabled modules" do
    @company.update!(disabled_modules: [ "pos", "reports" ])
    call(:post, "/addons", params: { module: "pos" })
    assert_response :created
    assert_equal [ "reports" ], @company.reload.disabled_modules
    assert @company.module_active?(:pos)
  end

  test "a failed prorated charge answers 402, nothing is activated and nothing is logged" do
    call(:post, "/addons", params: { module: "pos" }, charge_error: true)

    assert_response :payment_required
    assert_equal "addon_payment_failed", code
    assert_not @company.reload.module_active?(:pos)
    assert_equal 0, @company.module_changes.count
  end

  test "errors carry their code" do
    call(:post, "/addons", params: { module: "inventory" })
    assert_response :unprocessable_entity
    assert_equal "unknown_addon", code

    call(:post, "/addons", params: {})
    assert_response :bad_request

    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(@super, companies(:expired_co)))
    assert_response :unprocessable_entity
    assert_equal "subscription_not_paid", code
  end

  test "it is not turned on while its prices are missing" do
    with_env("ADDON_POS_ENABLED" => "false") do
      call(:post, "/addons", params: { module: "pos" })
    end
    assert_response :unprocessable_entity
    assert_equal "addon_not_available", code
    assert_empty @created
  end

  test "already on" do
    call(:post, "/addons", params: { module: "pos" })
    call(:post, "/addons", params: { module: "pos" })
    assert_response :unprocessable_entity
    assert_equal "addon_already_active", code
  end

  test "a branch cannot change the billing: it is changed in the parent company" do
    branch = Company.create!(name: "Sucursal", parent: @company)
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(@super, branch))
    assert_response :unprocessable_entity
    assert_equal "billing_managed_by_parent", code
    assert_empty @created
  end

  test "a demo company cannot pay" do
    Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear
    demo = Demo::Provision.call(plan: "basic", scenario: "basic_retail", locale: "es")
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(@super, demo.company))

    assert_response :forbidden
    assert_equal "demo_restricted", code
    assert_empty @created
  end

  # --- prueba ---

  test "in the trial it is turned on without a charge nor a Stripe item, and turning it off is immediate" do
    trial = companies(:one)
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(@super, trial))

    assert_response :created
    assert_empty @created
    row = trial.billing_subscription.addons.find_by!(module: "pos")
    assert_nil row.stripe_item_id
    assert_includes json["active_modules"], "pos"
    assert_equal 19_900, trial.module_changes.order(:id).last.amount_after_cents

    call(:delete, "/addons/pos", headers: auth_headers(@super, trial))
    assert_response :ok
    assert_nil trial.billing_subscription.addons.find_by(module: "pos")
    assert_empty @deleted
    assert_equal [ true, false ], trial.module_changes.order(:id).pluck(:enabled).last(2)
  end

  # --- apagar y reactivar ---

  test "DELETE addons/:module schedules the end, keeps the module until then and notifies" do
    grant_addon!(@company, :pos)
    call(:delete, "/addons/pos")

    assert_response :ok
    assert_equal "ending", json["addons"].first["status"]
    assert_not_nil json["addons"].first["ends_at"]
    assert_includes json["active_modules"], "pos"
    assert_equal 19_900, json["addons_cents"]
    change = @company.module_changes.order(:id).last
    assert_equal [ false, 19_900, 0 ], [ change.enabled, change.amount_before_cents, change.amount_after_cents ]
    assert_equal "off", @mails.first[:action]
    assert_not_nil @mails.first[:effective_on]
  end

  test "an add-on already over does not appear nor count" do
    grant_addon!(@company, :pos, ends_at: 1.hour.ago)
    get BASE, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_empty json["addons"]
    assert_equal 0, json["addons_cents"]
    assert_not_includes json["active_modules"], "pos"
    assert_equal 6_384, json["iva_cents"]
  end

  test "DELETE errors" do
    call(:delete, "/addons/pos")
    assert_response :not_found
    assert_equal "addon_not_found", code

    grant_addon!(@company, :pos)
    call(:delete, "/addons/pos")
    call(:delete, "/addons/pos")
    assert_response :unprocessable_entity
    assert_equal "addon_already_ending", code
  end

  test "POST addons/:module/reactivate undoes a pending end without charging" do
    grant_addon!(@company, :pos, ends_at: 5.days.from_now)
    call(:post, "/addons/pos/reactivate")

    assert_response :ok
    assert_equal "active", json["addons"].first["status"]
    assert_nil json["addons"].first["ends_at"]
  end

  test "reactivate without a pending end is rejected" do
    grant_addon!(@company, :pos)
    call(:post, "/addons/pos/reactivate")
    assert_response :unprocessable_entity
    assert_equal "addon_not_ending", code
  end

  # --- checkout ---

  test "the trial checkout carries the add-ons the super admin turned on and ignores what the client sends" do
    trial = companies(:one)
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(@super, trial))

    captured = with_memory_cache do
      with_checkout_stubs do
        post "#{BASE}/checkout", params: { plan: "pro", billing_cycle: "monthly", success_url: "https://a.test/ok", cancel_url: "https://a.test/no" },
                                 headers: auth_headers(users(:one_owner), trial), as: :json
      end
    end

    assert_response :ok
    assert_equal 2, captured[:line_items].size
  end

  test "the client cannot add an add-on through the checkout" do
    captured = with_memory_cache do
      with_checkout_stubs do
        post "#{BASE}/checkout", params: { plan: "pro", billing_cycle: "monthly", addons: [ "pos" ], success_url: "https://a.test/ok", cancel_url: "https://a.test/no" },
                                 headers: auth_headers(users(:one_owner), companies(:one)), as: :json
      end
    end

    assert_response :ok
    assert_equal 1, captured[:line_items].size
  end
end
