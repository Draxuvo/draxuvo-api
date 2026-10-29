require "test_helper"

class Whatsapp::ConfigTest < ActiveSupport::TestCase
  ENV_VARS = { "WHATSAPP_ACCESS_TOKEN" => "token-de-env", "WHATSAPP_PHONE_NUMBER_ID" => "999888777" }.freeze
  NO_ENV = { "WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil, "WHATSAPP_STOCK_TEMPLATE_NAME" => nil,
             "WHATSAPP_STOCK_TEMPLATE_LANG" => nil, "WHATSAPP_OTP_TEMPLATE_NAME" => nil, "WHATSAPP_OTP_TEMPLATE_LANG" => nil }.freeze

  setup { WhatsappMessageType.ensure_all! }

  def config = Whatsapp::Config.current

  # Deja el panel conectado, con el canal y el tipo encendidos y la plantilla aprobada.
  def panel_ready!(kind: "verification_code")
    WhatsappConnection.current.update!(access_token: "EAAGdelpanel0000", phone_number_id: "104512345678901", waba_id: "109876543210987",
                                       status: "connected", managed: true)
    WhatsappMessageType.find_by!(kind: kind).update!(template_status: "approved") if kind != "ticket"
    WhatsappConnection.current.update!(enabled: true)
    WhatsappMessageType.find_by!(kind: kind).update!(enabled: true)
  end

  test "with nothing configured there is no source and nothing is available" do
    with_env(NO_ENV) do
      assert_equal :none, config.source
      Whatsapp::MessageTypes.all.each { |type| assert_not config.available?(type.kind) }
    end
  end

  test "with only environment variables they keep working as before, for every type" do
    with_env(ENV_VARS) do
      assert_equal :env, config.source
      assert_equal [ "token-de-env", "999888777" ], [ config.access_token, config.phone_number_id ]
      Whatsapp::MessageTypes.all.each { |type| assert config.available?(type.kind) }
    end
  end

  test "an environment with only one of the two variables is not configured" do
    with_env(NO_ENV.merge("WHATSAPP_ACCESS_TOKEN" => "solo-token")) { assert_equal :none, config.source }
  end

  test "touching the connection row without using the panel does not take control from the environment" do
    WhatsappConnection.current
    with_env(ENV_VARS) { assert_equal :env, config.source }
  end

  test "once the panel is used it wins and the environment variables are ignored" do
    with_env(ENV_VARS) do
      panel_ready!
      assert_equal :panel, config.source
      assert_equal [ "EAAGdelpanel0000", "104512345678901", "109876543210987" ], [ config.access_token, config.phone_number_id, config.waba_id ]
    end
  end

  test "disconnecting does not bring the old environment variables back" do
    with_env(ENV_VARS) do
      panel_ready!
      WhatsappConnection.current.disconnect!

      assert_equal :panel, config.source
      assert_nil config.access_token
      Whatsapp::MessageTypes.all.each { |type| assert_not config.available?(type.kind) }
    end
  end

  test "a type is available only with the connection, the general switch, its own switch and an approved template" do
    with_env(NO_ENV) do
      panel_ready!
      assert config.available?("verification_code")
      assert config.available?(:verification_code)
      assert_not config.available?("ticket"), "el otro tipo sigue apagado"

      WhatsappMessageType.find_by!(kind: "verification_code").update!(enabled: false)
      assert_not config.available?("verification_code")
    end
  end

  test "turning the general switch off makes every type unavailable but keeps the choices" do
    with_env(NO_ENV) do
      panel_ready!
      WhatsappConnection.current.update!(enabled: false)

      assert_not config.available?("verification_code")
      assert WhatsappMessageType.find_by!(kind: "verification_code").enabled
    end
  end

  test "a type whose template stopped being approved is unavailable" do
    with_env(NO_ENV) do
      panel_ready!
      WhatsappMessageType.find_by!(kind: "verification_code").update_columns(template_status: "rejected")
      assert_not config.available?("verification_code")
    end
  end

  test "a connection in error makes everything unavailable without touching the switches" do
    with_env(NO_ENV) do
      panel_ready!
      WhatsappConnection.current.update!(status: "error")

      assert_not config.available?("verification_code")
      assert WhatsappConnection.current.enabled
    end
  end

  test "tickets only need the connection and their own switch, no template" do
    with_env(NO_ENV) do
      panel_ready!(kind: "ticket")
      assert config.available?("ticket")
      assert_nil config.template_for("ticket")
    end
  end

  test "templates come from the panel, or from the environment with their defaults and overrides" do
    with_env(NO_ENV) do
      panel_ready!
      WhatsappMessageType.find_by!(kind: "verification_code").update_columns(template_name: "mi_plantilla", template_language: "en_US")
      assert_equal %w[mi_plantilla en_US], config.template_for("verification_code").to_a
    end

    with_env(ENV_VARS) do
      WhatsappConnection.current.update_columns(managed: false)
      assert_equal %w[verification_code es_MX], config.template_for("verification_code").to_a
    end

    with_env(ENV_VARS.merge("WHATSAPP_OTP_TEMPLATE_NAME" => "otra", "WHATSAPP_OTP_TEMPLATE_LANG" => "es")) do
      assert_equal %w[otra es], config.template_for("verification_code").to_a
    end
  end

  test "the old low stock template variables are ignored (spec 048)" do
    with_env(ENV_VARS.merge("WHATSAPP_STOCK_TEMPLATE_NAME" => "otra", "WHATSAPP_STOCK_TEMPLATE_LANG" => "en_US")) do
      assert_equal %w[verification_code es_MX], config.template_for("verification_code").to_a
      assert_not_includes Whatsapp::Config::ENV_TEMPLATES.keys, "stock_alert"
    end
  end

  test "a key that can no longer be read makes the panel unavailable and is reported" do
    with_env(NO_ENV) do
      panel_ready!
      WhatsappConnection.where(id: WhatsappConnection.current.id).update_all("access_token = 'no-es-un-texto-cifrado'")

      assert config.key_unreadable?
      assert_nil config.access_token
      assert_not config.available?("verification_code")
    end
  end

  test "reading the configuration never creates rows" do
    WhatsappConnection.delete_all
    WhatsappMessageType.delete_all

    assert_no_difference [ "WhatsappConnection.count", "WhatsappMessageType.count" ] do
      with_env(NO_ENV) { config.available?("verification_code") }
    end
  end

  test "the client is built with the resolved key" do
    with_env(ENV_VARS) { assert_instance_of Whatsapp::GraphClient, config.client }
  end
end
