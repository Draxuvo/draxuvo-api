require "test_helper"

class Push::MessageTest < ActiveSupport::TestCase
  setup { @company = companies(:resto_co) }

  def device(locale) = PushDevice.new(token: "ExponentPushToken[x]", locale: locale, platform: "android")

  test "builds title, body, data and channel in the device language" do
    message = Push::Message.new(kind: "check_ready", company: @company, path: "/pedido?cuenta=1&hoja=1", subject_id: 1,
                                body_key: "check_ready_table", body_args: { table: "4", count: 2 })

    es = message.for_device(device("es"))
    assert_equal "Restaurante Prueba · Comanda lista", es[:title]
    assert_equal "Mesa 4 · 2 artículos listos", es[:body]
    assert_equal({ kind: "check_ready", company_id: @company.id, path: "/pedido?cuenta=1&hoja=1", subject_id: 1 }, es[:data])
    assert_equal "orders", es[:channelId]
    assert_equal 300, es[:ttl]

    en = message.for_device(device("en"))
    assert_equal "Restaurante Prueba · Order ready", en[:title]
    assert_equal "Table 4 · 2 items ready", en[:body]
  end

  test "every body template stays free of amounts and customer data (FR-016, SC-003)" do
    %w[es en].each do |locale|
      bodies = I18n.t("push.bodies", locale: locale)
      bodies.each_value do |value|
        Array(value.is_a?(Hash) ? value.values : value).each do |text|
          assert_no_match(/\$|%\{(total|amount|price|customer|phone|address|salary)/, text, "#{locale}: #{text}")
        end
      end
    end
  end
end
