require "test_helper"

class Alerts::RecipientsTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @company.user_companies.where(role: %i[owner admin]).delete_all
    @owner = create_member(@company, role: :owner)
    @admin = create_member(@company, role: :admin)
    @staff = create_member(@company, role: :staff)
  end

  def recipients = Alerts::Recipients.call(@company).index_by(&:user)

  test "owners and admins get the email by default, staff never" do
    found = recipients
    assert_equal [ @owner, @admin ].sort_by(&:id), found.keys.sort_by(&:id)
    assert found.values.all?(&:email)
  end

  test "a recipient only carries the email channel, never WhatsApp" do
    recipient = recipients.fetch(@owner)

    assert_not_respond_to recipient, :whatsapp
    assert_equal %i[email user], recipient.to_h.keys.sort
  end

  test "an old WhatsApp preference does not make anyone a recipient or change their email" do
    NotificationPreference.create!(user: @owner, company: @company, stock_whatsapp: true)
    # Con el correo apagado, WhatsApp ya no la mantiene como destinatario.
    NotificationPreference.create!(user: @admin, company: @company, stock_email: false, stock_whatsapp: true)

    found = recipients
    assert found.fetch(@owner).email
    assert_not_includes found.keys, @admin
  end

  test "the phone no longer matters: someone without a phone still gets the email" do
    @owner.update_column(:phone, nil)

    assert recipients.fetch(@owner).email
  end

  test "a person with the email off is not a recipient" do
    NotificationPreference.create!(user: @admin, company: @company, stock_email: false)
    assert_equal [ @owner ], recipients.keys
  end

  test "an inactive employee, an inactive user or someone who is no longer a boss is left out" do
    @company.employees.create!(name: "Baja", user: @admin, status: :inactive)
    assert_equal [ @owner ], recipients.keys

    @owner.update_column(:active, false)
    assert_empty recipients

    @owner.update_column(:active, true)
    @company.user_companies.find_by!(user: @owner).update!(role: :staff)
    assert_equal [], recipients.keys - [ @admin ]
    assert_not_includes recipients.keys, @owner
  end

  test "preferences of the same person in another company do not leak" do
    other = companies(:one)
    UserCompany.create!(user: @owner, company: other, role: :owner)
    NotificationPreference.create!(user: @owner, company: other, stock_email: false)
    assert recipients.fetch(@owner).email
  end
end
