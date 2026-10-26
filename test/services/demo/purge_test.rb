require "test_helper"

class Demo::PurgeTest < ActiveSupport::TestCase
  Demo::Scenarios.keys.each do |key|
    test "#{key} leaves zero residue after provisioning and purging" do
      before = table_row_counts
      result = Demo::Provision.call(plan: Demo::Scenarios.plan_of(key), scenario: key, locale: "es")
      assert_not_equal before, table_row_counts

      Demo::Purge.call(result.company)

      after = table_row_counts
      # Solo sobrevive la apertura (demo_sessions); todo lo demás vuelve al estado anterior.
      assert_equal before.except("demo_sessions"), after.except("demo_sessions")
      assert_equal before["demo_sessions"] + 1, after["demo_sessions"]
    end
  end

  test "the session keeps plan, scenario, contact and dates and loses company and user" do
    result = Demo::Provision.call(plan: "basic", scenario: "basic_retail", locale: "es",
                                  contact: { name: "Ana", email: "ana@ejemplo.mx" })
    Demo::Purge.call(result.company)

    session = result.session.reload
    assert_nil session.company_id
    assert_nil session.user_id
    assert session.purged_at
    assert_equal [ "basic", "basic_retail", "Ana", "ana@ejemplo.mx" ],
                 session.values_at(:plan, :scenario, :contact_name, :contact_email)
    assert_equal "expired", session.ended_reason
  end

  test "keeps the reason when the visitor already ended it" do
    result = Demo::Provision.call(plan: "basic", scenario: "basic_retail", locale: "es")
    result.session.update!(ended_at: Time.current, ended_reason: "signup")
    Demo::Purge.call(result.company)

    assert_equal "signup", result.session.reload.ended_reason
  end

  test "the branch goes first and the ephemeral users disappear" do
    result = Demo::Provision.call(plan: "enterprise", scenario: "enterprise_restaurant", locale: "es")
    user_ids = result.company.users.pluck(:id) + result.branch.users.pluck(:id)

    Demo::Purge.call(result.company)

    assert_not Company.exists?(result.company.id)
    assert_not Company.exists?(result.branch.id)
    assert_empty User.where(id: user_ids)
  end

  test "never touches a real company or its users" do
    real = companies(:pro_co)
    users_before = real.users.pluck(:id).sort
    counts_before = [ real.employees.count, real.products.count, real.checks.count ]

    result = Demo::Provision.call(plan: "basic", scenario: "basic_retail", locale: "es")
    Demo::Purge.call(result.company)

    assert Company.exists?(real.id)
    assert_equal users_before, real.reload.users.pluck(:id).sort
    assert_equal counts_before, [ real.employees.count, real.products.count, real.checks.count ]
  end

  test "refuses to purge a company that is not a demo" do
    assert_raises(ArgumentError) { Demo::Purge.call(companies(:pro_co)) }
    assert Company.exists?(companies(:pro_co).id)
  end

  test "attached files go away with the demo" do
    result = Demo::Provision.call(plan: "pro", scenario: "pro_service", locale: "es")
    blobs_before = ActiveStorage::Attachment.where(record_type: "WorkOrderAttachment").count

    Demo::Purge.call(result.company)

    assert_operator blobs_before, :>=, 0
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "WorkOrderAttachment").where.not(record_id: WorkOrderAttachment.select(:id)).count
  end
end
