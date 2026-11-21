require "test_helper"

# Spec 071 (US3): campos propios de la línea JSON de cada petición (contracts/log-line.md).
class RequestLogTest < ActiveSupport::TestCase
  Event = Struct.new(:payload)

  def payload(**extra)
    {
      controller: "Api::V1::ProductsController", action: "index", method: "GET", path: "/api/v1/products?search=Juan",
      params: { "search" => "Juan", "email" => "cliente@correo.com" }, headers: { "Authorization" => "Bearer x" },
      request_id: "req-123", user_id: 42, company_id: 23, demo: false
    }.merge(extra)
  end

  test "adds request_id, user, company and demo, and nothing from params or headers" do
    options = RequestLog.custom_options(Event.new(payload))

    assert_equal({ request_id: "req-123", user_id: 42, company_id: 23, demo: false }, options)
    assert_not_includes options.inspect, "Juan"
    assert_not_includes options.inspect, "cliente@correo.com"
    assert_not_includes options.inspect, "Bearer"
  end

  test "a 500 adds only the exception class, never its message" do
    options = RequestLog.custom_options(Event.new(payload(exception: [ "NoMethodError", "undefined method for cliente@correo.com" ])))

    assert_equal "NoMethodError", options[:exception]
    assert_not_includes options.inspect, "cliente@correo.com"
  end

  test "an anonymous request keeps the keys with nil values" do
    options = RequestLog.custom_options(Event.new(payload(user_id: nil, company_id: nil, demo: nil)))

    assert_nil options[:user_id]
    assert_nil options[:company_id]
    assert_not options.key?(:exception)
  end
end
