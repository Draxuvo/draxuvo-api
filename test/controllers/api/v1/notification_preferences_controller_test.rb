require "test_helper"

# Contrato: specs/045-alertas-operativas/contracts/api.md (/notification_preference).
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

  test "GET returns the defaults, whether there is a phone and whether WhatsApp is available" do
    with_env("WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil) do
      get PATH, headers: auth_headers(@owner, @company)
    end

    assert_response :ok
    assert_equal({ "stock_email" => true, "stock_whatsapp" => false, "phone_present" => true, "whatsapp_available" => false }, json)
  end

  test "whatsapp_available is true once the server has WhatsApp configured" do
    with_env("WHATSAPP_ACCESS_TOKEN" => "t", "WHATSAPP_PHONE_NUMBER_ID" => "1") do
      get PATH, headers: auth_headers(@owner, @company)
    end
    assert json["whatsapp_available"]
  end

  test "PATCH saves the channels of this person in this company only" do
    patch_pref({ stock_email: false, stock_whatsapp: true })

    assert_response :ok
    assert_equal [ false, true ], json.values_at("stock_email", "stock_whatsapp")
    preference = NotificationPreference.find_by!(user: @owner, company: @company)
    assert_equal [ false, true ], [ preference.stock_email, preference.stock_whatsapp ]

    other = companies(:one)
    UserCompany.create!(user: @owner, company: other, role: :admin)
    get PATH, headers: auth_headers(@owner, other)
    assert_equal [ true, false ], json.values_at("stock_email", "stock_whatsapp")
  end

  test "a partial PATCH leaves the other channel as it was" do
    patch_pref({ stock_email: false })
    patch_pref({ stock_whatsapp: true })
    assert_equal [ false, true ], json.values_at("stock_email", "stock_whatsapp")
  end

  test "turning WhatsApp on without a phone is rejected with phone_required" do
    @owner.update_column(:phone, nil)
    patch_pref({ stock_whatsapp: true })

    assert_response :unprocessable_entity
    assert_equal [ { "code" => "phone_required" } ], json.dig("error", "details")
    assert_equal 0, NotificationPreference.count

    get PATH, headers: auth_headers(@owner, @company)
    assert_equal false, json["phone_present"]
  end

  test "turning WhatsApp off is always allowed, even without a phone" do
    NotificationPreference.create!(user: @owner, company: @company, stock_whatsapp: true)
    @owner.update_column(:phone, nil)
    patch_pref({ stock_whatsapp: false })
    assert_response :ok
  end

  test "staff cannot use it" do
    waiter = create_member(@company, role: :staff)
    get PATH, headers: auth_headers(waiter, @company)
    assert_response :forbidden
    patch_pref({ stock_email: false }, user: waiter)
    assert_response :forbidden
  end
end
