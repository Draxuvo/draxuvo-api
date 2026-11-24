require "test_helper"

# Spec 073: cada intento de POST /auth/login deja un renglón en la bitácora, sin la contraseña, y el login responde igual
# aunque la bitácora falle.
class Api::V1::AuthenticationControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "Clave-Segura-9".freeze
  WRONG = "Contrasena-Mala-77".freeze

  setup do
    Api::V1::AuthenticationController::RATE_LIMIT_STORE.clear
    @user = users(:pro_staff)
  end

  def login(email, password, headers: {})
    post "/api/v1/auth/login", params: { email: email, password: password }, headers: headers, as: :json
  end

  def last_attempt = LoginAttempt.order(:id).last

  test "success is recorded with the person and the panel channel" do
    assert_difference("LoginAttempt.count", 1) do
      login(@user.email.upcase, PASSWORD, headers: { "X-Draxuvo-Client" => "panel" })
    end
    assert_response :ok
    assert_equal [ "success", @user.id, @user.email, "panel" ], [ last_attempt.result, last_attempt.user_id, last_attempt.email, last_attempt.channel ]
  end

  test "each failure is recorded with its result" do
    login(@user.email, WRONG)
    assert_response :unauthorized
    assert_equal [ "wrong_password", @user.id ], [ last_attempt.result, last_attempt.user_id ]

    login("nadie@ejemplo.test", WRONG)
    assert_response :not_found
    assert_equal [ "unknown_email", nil ], [ last_attempt.result, last_attempt.user_id ]

    @user.update!(active: false)
    login(@user.email, PASSWORD)
    assert_response :forbidden
    assert_equal [ "inactive", @user.id ], [ last_attempt.result, last_attempt.user_id ]
  end

  test "invalid input is recorded only when there is an email" do
    login("correo-sin-arroba", WRONG)
    assert_response :bad_request
    assert_equal [ "invalid", "correo-sin-arroba" ], [ last_attempt.result, last_attempt.email ]

    assert_no_difference("LoginAttempt.count") { login("", WRONG) }
    assert_response :bad_request
  end

  test "the attempt over the limit is recorded as rate limited" do
    10.times { login(@user.email, WRONG) }
    assert_difference("LoginAttempt.count", 1) { login(@user.email, PASSWORD) }
    assert_response :too_many_requests
    assert_equal [ "rate_limited", @user.id ], [ last_attempt.result, last_attempt.user_id ]
  end

  test "the password is never stored" do
    login(@user.email, WRONG)
    login(@user.email, PASSWORD)
    stored = LoginAttempt.all.map(&:attributes).to_s
    assert_not_includes stored, WRONG
    assert_not_includes stored, PASSWORD
  end

  test "the login answers exactly the same when the log cannot be saved" do
    cases = [ [ @user.email, PASSWORD ], [ @user.email, WRONG ], [ "nadie@ejemplo.test", WRONG ], [ "x@", WRONG ] ]
    expected = cases.to_h do |email, password|
      login(email, password)
      [ [ email, password ], [ response.status, response.parsed_body.except("token") ] ]
    end
    Api::V1::AuthenticationController::RATE_LIMIT_STORE.clear

    LoginAttempt.stub(:create!, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      Sentry.stub(:capture_exception, ->(*, **) { }) do
        expected.each do |(email, password), (status, body)|
          login(email, password)
          assert_equal status, response.status, email
          assert_equal body, response.parsed_body.except("token"), email
        end

        login(@user.email, PASSWORD)
        assert_response :ok
        assert response.parsed_body["token"].present?
      end
    end
  end
end
