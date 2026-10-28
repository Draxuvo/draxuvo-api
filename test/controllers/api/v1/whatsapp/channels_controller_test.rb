require "test_helper"

# Spec 047, US3: interruptor general del canal. Apagar siempre se puede; encender exige una conexión válida.
class WhatsappChannelsControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "EAAGtokensecreto1234567890".freeze
  PATH = "/api/v1/whatsapp/channel".freeze

  setup do
    @headers = auth_headers(users(:super_admin), nil)
    @connection = WhatsappConnection.current
  end

  def connect!
    @connection.update!(access_token: TOKEN, phone_number_id: "104512345678901", waba_id: "109876543210987", status: "connected", managed: true)
  end

  def patch_channel(params, headers: @headers)
    patch PATH, params: params, headers: headers, as: :json
  end

  test "turning the channel on without a connection answers 422 not_connected and changes nothing" do
    patch_channel({ enabled: true })

    assert_response :unprocessable_entity
    assert_equal "not_connected", response.parsed_body.dig("error", "details", "code")
    assert_not @connection.reload.enabled?
    assert_not WhatsappEvent.exists?(action: "channel_on")
  end

  test "turning the channel on with a connection in error answers 422 connection_error" do
    connect!
    @connection.update!(status: "error")

    patch_channel({ enabled: true })

    assert_response :unprocessable_entity
    assert_equal "connection_error", response.parsed_body.dig("error", "details", "code")
  end

  test "turning the channel on with a valid connection works and is logged" do
    connect!

    patch_channel({ enabled: true, lock_version: @connection.lock_version })

    assert_response :ok
    assert_equal true, response.parsed_body.dig("connection", "enabled")
    assert @connection.reload.enabled?
    event = WhatsappEvent.find_by!(action: "channel_on")
    assert_equal users(:super_admin).id, event.user_id
  end

  test "turning the channel off keeps what was chosen for each type" do
    connect!
    WhatsappMessageType.ensure_all!
    WhatsappMessageType.find_by!(kind: "ticket").update!(enabled: true)
    @connection.update!(enabled: true)

    patch_channel({ enabled: false })

    assert_response :ok
    assert_not @connection.reload.enabled?
    assert WhatsappMessageType.find_by!(kind: "ticket").enabled?
    assert WhatsappEvent.exists?(action: "channel_off")
  end

  test "turning off a channel that is already off is not an error and logs nothing" do
    patch_channel({ enabled: false })

    assert_response :ok
    assert_not WhatsappEvent.exists?(action: "channel_off")
  end

  test "an off channel can always be turned off even with a connection in error" do
    connect!
    @connection.update_columns(enabled: true, status: "error")

    patch_channel({ enabled: false })

    assert_response :ok
    assert_not @connection.reload.enabled?
  end

  test "disconnecting and connecting again leaves the channel and the types off" do
    connect!
    WhatsappMessageType.ensure_all!
    WhatsappMessageType.find_by!(kind: "ticket").update!(enabled: true)
    @connection.update!(enabled: true)

    @connection.reload.disconnect!
    connect!

    assert_not @connection.reload.enabled?
    assert_not WhatsappMessageType.where(enabled: true).exists?
  end

  test "enabled is required" do
    patch_channel({})

    assert_response :bad_request
  end

  test "an old lock version answers 409 stale_object" do
    connect!

    patch_channel({ enabled: true, lock_version: @connection.lock_version + 3 })

    assert_response :conflict
    assert_equal "stale_object", response.parsed_body.dig("error", "details", "code")
  end

  test "owner, admin and staff are forbidden" do
    company = companies(:enterprise_co)
    %w[owner admin staff].each do |role|
      patch_channel({ enabled: true }, headers: auth_headers(create_member(company, role: role), company))

      assert_response :forbidden, "PATCH as #{role}"
    end
  end
end
