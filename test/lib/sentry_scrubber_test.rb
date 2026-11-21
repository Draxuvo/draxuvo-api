require "test_helper"

# Spec 071: ningún evento de error sale con datos personales, tokens ni cuerpos (contracts/error-event.md).
class SentryScrubberTest < ActiveSupport::TestCase
  Request = Struct.new(:url, :method, :data, :query_string, :cookies, :headers, :env, keyword_init: true)
  Event = Struct.new(:request, :user, keyword_init: true)

  def dirty_event
    Event.new(
      request: Request.new(
        url: "https://api.draxuvo.com/api/v1/work_orders?search=Juan%20P%C3%A9rez&token=abc123#frag",
        method: "POST",
        data: { "email" => "cliente@correo.com", "password" => "secreta" },
        query_string: "search=Juan&token=abc123",
        cookies: { "session" => "x" },
        headers: { "Authorization" => "Bearer eyJ…", "Cookie" => "a=b", "X-Company-Id" => "23", "User-Agent" => "Mozilla/5.0" },
        env: { "REMOTE_ADDR" => "187.0.0.1" }
      ),
      user: { id: 42, email: "dueno@negocio.mx", username: "Dueño", ip_address: "187.0.0.1" }
    )
  end

  test "removes body, cookies, query string, env and every header except User-Agent" do
    request = SentryScrubber.call(dirty_event).request

    assert_nil request.data
    assert_nil request.cookies
    assert_nil request.query_string
    assert_nil request.env
    assert_equal({ "User-Agent" => "Mozilla/5.0" }, request.headers)
    assert_equal "https://api.draxuvo.com/api/v1/work_orders", request.url
    assert_equal "POST", request.method
  end

  test "keeps only the user id" do
    assert_equal({ id: 42 }, SentryScrubber.call(dirty_event).user)
  end

  test "an event without request nor user passes through" do
    event = Event.new(request: nil, user: nil)

    assert_same event, SentryScrubber.call(event)
    assert_equal({}, event.user)
  end

  test "nothing personal survives anywhere in the event" do
    dumped = SentryScrubber.call(dirty_event).to_h.inspect

    %w[cliente@correo.com dueno@negocio.mx secreta Bearer abc123 Juan 187.0.0.1 Dueño].each do |secret|
      assert_not_includes dumped, secret
    end
  end
end
