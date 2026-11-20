require "test_helper"

# Spec 071 (US2, FR-005/FR-006/FR-007): ErrorHandler atrapa StandardError y responde 500, así que el middleware de Sentry
# nunca vería el error: se reporta a mano. Los 4xx esperados no se reportan. Cada petición autenticada deja en el contexto
# de Sentry solo el id del usuario, la empresa y si es demo.
class ErrorReportingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:pro_co_owner)
    @company = companies(:pro_co)
    @headers = auth_headers(@owner, @company)
  end

  def capturing_sentry
    captured = []
    Sentry.stub(:capture_exception, ->(error, **_options) { captured << error }) { yield captured }
    captured
  end

  # Hace fallar una acción real con un error inesperado y la restaura al terminar.
  def with_failing_action(controller, action, error)
    original = controller.instance_method(action)
    controller.define_method(action) { raise error }
    yield
  ensure
    controller.define_method(action, original)
  end

  test "an unexpected error is reported once and the client still gets the same 500" do
    error = RuntimeError.new("se rompió el tablero")
    captured = capturing_sentry do
      with_failing_action(Api::V1::DashboardController, :index, error) do
        get "/api/v1/dashboard", headers: @headers
      end
    end

    assert_response :internal_server_error
    body = response.parsed_body
    assert_equal 500, body.dig("error", "status")
    assert_equal I18n.t("errors.internal"), body.dig("error", "message")
    assert_equal [ error ], captured
  end

  test "expected 4xx responses are not reported" do
    captured = capturing_sentry do
      get "/api/v1/products", headers: { "Authorization" => "Bearer invalido", "X-Company-Id" => @company.id.to_s }
      assert_response :unauthorized

      get "/api/v1/products/999999999", headers: @headers
      assert_response :not_found

      get "/api/v1/products", params: { page: "abc" }, headers: @headers
      assert_response :unprocessable_entity

      get "/api/v1/sales", headers: @headers
      assert_response :forbidden
      assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
    end

    assert_empty captured
  end

  test "an authenticated request sets only the user id, the company and the demo flag" do
    users = []
    tags = []
    Sentry.stub(:set_user, ->(user) { users << user }) do
      Sentry.stub(:set_tags, ->(values) { tags << values }) do
        get "/api/v1/products", headers: @headers
      end
    end

    assert_response :ok
    assert_equal [ { id: @owner.id } ], users
    assert_equal [ { company_id: @company.id, demo: false } ], tags
  end
end
