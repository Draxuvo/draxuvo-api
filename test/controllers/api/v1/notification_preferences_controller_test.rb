require "test_helper"

# Contrato: specs/048-quitar-whatsapp-avisos/contracts/api.md (/notification_preference). Desde la spec 048 el stock
# bajo solo sale por correo: `stock_whatsapp` ya no se lee, no se escribe ni se devuelve.
class Api::V1::NotificationPreferencesControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/notification_preference".freeze

  setup do
    @company = companies(:pro_co)
    @owner = create_member(@company, role: :owner)
  end

  def json = JSON.parse(response.body)

  def patch_pref(body, user: @owner, company: @company)
    patch PATH, params: body, headers: auth_headers(user, company), as: :json
  end

  test "GET returns only the email channel, on by default" do
    get PATH, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal({ "stock_email" => true }, json)
  end

  test "GET never exposes WhatsApp, the phone or availability, even if the server has WhatsApp configured" do
    with_env("WHATSAPP_ACCESS_TOKEN" => "t", "WHATSAPP_PHONE_NUMBER_ID" => "1") do
      get PATH, headers: auth_headers(@owner, @company)
    end

    assert_equal %w[stock_email], json.keys
  end

  test "PATCH saves the email channel of this person in this company only" do
    patch_pref({ stock_email: false })

    assert_response :ok
    assert_equal({ "stock_email" => false }, json)
    assert_not NotificationPreference.find_by!(user: @owner, company: @company).stock_email

    other = companies(:one)
    UserCompany.create!(user: @owner, company: other, role: :admin)
    get PATH, headers: auth_headers(@owner, other)
    assert_equal({ "stock_email" => true }, json)
  end

  test "an old client that sends stock_whatsapp is not rejected: the value is ignored and not returned" do
    patch_pref({ stock_whatsapp: true })

    assert_response :ok
    assert_equal({ "stock_email" => true }, json)
    assert_not NotificationPreference.find_by!(user: @owner, company: @company).stock_whatsapp
  end

  test "stock_whatsapp next to stock_email only applies the email" do
    patch_pref({ stock_email: false, stock_whatsapp: true })

    assert_response :ok
    assert_equal({ "stock_email" => false }, json)
    preference = NotificationPreference.find_by!(user: @owner, company: @company)
    assert_equal [ false, false ], [ preference.stock_email, preference.stock_whatsapp ]
  end

  test "an old WhatsApp preference without a phone does not block saving the email (no phone_required)" do
    NotificationPreference.create!(user: @owner, company: @company, stock_whatsapp: true)
    @owner.update_column(:phone, nil)

    patch_pref({ stock_email: false })

    assert_response :ok
    assert_equal({ "stock_email" => false }, json)
    assert NotificationPreference.find_by!(user: @owner, company: @company).stock_whatsapp, "el valor histórico se conserva sin tocarlo"
  end

  test "staff cannot use it" do
    waiter = create_member(@company, role: :staff)
    get PATH, headers: auth_headers(waiter, @company)
    assert_response :forbidden
    patch_pref({ stock_email: false }, user: waiter)
    assert_response :forbidden
  end

  test "without a session it is unauthorized" do
    get PATH

    assert_response :unauthorized
  end
end
