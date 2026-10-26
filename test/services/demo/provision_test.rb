require "test_helper"

class Demo::ProvisionTest < ActiveSupport::TestCase
  def provision(plan: "basic", scenario: "basic_retail", **extra)
    Demo::Provision.call(plan: plan, scenario: scenario, locale: "es", **extra)
  end

  test "creates a demo company with an active subscription of the plan and a one-year period" do
    result = provision

    company = result.company
    assert company.demo?
    subscription = company.subscription
    assert subscription.active?
    assert_equal "basic", subscription.plan
    assert_equal 0, subscription.amount_cents
    assert_operator subscription.current_period_end, :>, 11.months.from_now
    assert company.active_modules.sort == Plan.find(:basic).modules.sort
  end

  test "creates an ephemeral owner on the reserved domain who belongs only to the demo company" do
    result = provision

    user = result.user
    assert_match(/\Ademo-[0-9a-f]+@demo\.invalid\z/, user.email)
    assert user.active?
    assert_equal [ result.company.id ], user.user_companies.pluck(:company_id)
    assert_equal "owner", user.role_in(result.company)
  end

  test "the owner of the enterprise demo belongs to the company and its branch" do
    result = provision(plan: "enterprise", scenario: "enterprise_restaurant")

    assert_equal [ result.branch.id, result.company.id ].sort, result.user.user_companies.pluck(:company_id).sort
  end

  test "the token expires with the demo and carries the user" do
    result = provision

    payload = JwtHelper.jwt_decode(result.token)
    assert_equal result.user.id, payload[:user_id]
    assert_equal result.session.expires_at.to_i, payload[:exp]
    assert_in_delta Demo::Config.ttl.from_now.to_i, payload[:exp], 5
  end

  test "records the session with the contact and the invite" do
    invite, = DemoInvite.issue!(plan: "basic", scenario: "basic_retail", label: "Café La Plaza")
    result = provision(contact: { name: "Ana", email: "ana@ejemplo.mx", phone: "5512345678" }, invite: invite)

    session = result.session
    assert_equal result.company, session.company
    assert_equal result.user, session.user
    assert_equal invite, session.demo_invite
    assert_equal [ "basic", "basic_retail", "es", "Ana", "ana@ejemplo.mx", "5512345678" ],
                 session.values_at(:plan, :scenario, :locale, :contact_name, :contact_email, :contact_phone)
    assert session.usable?
  end

  test "a failure halfway leaves no rows behind" do
    before = table_row_counts
    Demo::Scenarios::BasicRetail.stub(:call, ->(**) { raise "boom" }) do
      assert_raises(RuntimeError) { provision }
    end

    assert_equal before, table_row_counts
  end

  test "rejects a scenario that does not belong to the plan" do
    assert_raises(ArgumentError) { provision(plan: "basic", scenario: "pro_service") }
  end

  test "with all the provisioning slots taken by other sessions it raises Demo::Busy and creates nothing" do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(dbname: config[:database], user: config[:username], password: config[:password], host: config[:host])
    begin
      Demo::Config.max_provisioning.times do |slot|
        assert_equal "t", other.exec("SELECT pg_try_advisory_lock(#{Demo::Provision::LOCK_KEY}, #{slot})").getvalue(0, 0)
      end
      before = table_row_counts

      assert_raises(Demo::Busy) { provision }
      assert_equal before, table_row_counts
    ensure
      other.exec("SELECT pg_advisory_unlock_all()")
      other.close
    end
  end

  test "frees its slot when it finishes, even if it fails" do
    Demo::Scenarios::BasicRetail.stub(:call, ->(**) { raise "boom" }) do
      assert_raises(RuntimeError) { provision }
    end

    assert_nothing_raised { provision }
  end
end
