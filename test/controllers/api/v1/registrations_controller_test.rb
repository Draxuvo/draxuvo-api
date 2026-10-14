require "test_helper"

# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (POST /registrations).
class Api::V1::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  FakeWelcome = Struct.new(:calls) do
    def call = (calls << :sent) && { success: true }
  end

  def setup
    Api::V1::RegistrationsController::RATE_LIMIT_STORE.clear
    @welcome_args = []
  end

  def valid_params(overrides = {})
    {
      registration: {
        first_name: "Ana",
        last_name: "López",
        phone: "5512345678",
        email: "Ana@Ejemplo.com",
        password: "secreta123",
        company_name: "Café Ana",
        plan: "basic",
        billing_cycle: "annual"
      }.merge(overrides)
    }
  end

  # Evita llamar a Resend: captura los argumentos con los que se construye el correo.
  def register(params = valid_params)
    fake = FakeWelcome.new([])
    builder = lambda do |user, **kwargs|
      @welcome_args << [ user, kwargs ]
      fake
    end
    Email::WelcomeService.stub(:new, builder) do
      post "/api/v1/registrations", params: params, as: :json
    end
  end

  test "201 con { token, user }, owner activo, correo en minúsculas y sesión válida" do
    assert_difference [ "Company.count", "User.count", "UserCompany.count", "Subscription.count" ], 1 do
      register
    end

    assert_response :created
    body = response.parsed_body
    assert_equal %w[token user], body.keys.sort

    user = User.find(body["user"]["id"])
    assert_equal "ana@ejemplo.com", user.email
    assert_equal "owner", user.user_companies.sole.role
    assert user.active?
    assert_equal "owner", body["user"]["role"]
    assert_equal [ "Café Ana" ], body["user"]["companies"].map { |c| c["name"] }

    decoded = JwtHelper.jwt_decode(body["token"])
    assert_equal user.id, decoded[:user_id]
  end

  test "la prueba queda en el plan elegido, trialing, 30 días y el ciclo como preferencia" do
    register

    company = User.find_by!(email: "ana@ejemplo.com").companies.first
    subscription = company.subscription
    assert subscription.trialing?
    assert subscription.basic?
    assert subscription.annual?
    assert_in_delta 30.days.from_now, subscription.trial_ends_at, 1.minute
    assert_equal "cafe-ana", company.slug
  end

  test "billing_cycle es opcional y por defecto monthly" do
    register(valid_params(billing_cycle: nil))

    assert_response :created
    assert User.find_by!(email: "ana@ejemplo.com").companies.first.subscription.monthly?
  end

  test "envía el correo de bienvenida con la empresa y la fecha de fin de la prueba" do
    register

    assert_equal 1, @welcome_args.size
    user, kwargs = @welcome_args.first
    company = user.companies.first
    assert_equal "ana@ejemplo.com", user.email
    assert_equal "Café Ana", kwargs[:company_name]
    assert_equal company.subscription.trial_ends_at, kwargs[:trial_ends_at]
  end

  test "correo ya registrado (sin importar mayúsculas): 422 y no crea empresa" do
    existing = users(:pro_co_owner)
    assert_no_difference [ "Company.count", "User.count", "Subscription.count" ] do
      register(valid_params(email: existing.email.upcase))
    end

    assert_response :unprocessable_entity
    error = response.parsed_body["error"]
    assert_equal 422, error["status"]
    assert_kind_of Array, error["details"]
    assert error["details"].any? { |d| d.start_with?("Email") }
    assert_empty @welcome_args
  end

  test "campos faltantes: 422 con full_messages y no crea nada" do
    assert_no_difference [ "Company.count", "User.count" ] do
      register(valid_params(phone: "", password: ""))
    end

    assert_response :unprocessable_entity
    assert_kind_of Array, response.parsed_body["error"]["details"]
  end

  test "plan inválido: 400 con errors.subscription.invalid_plan" do
    assert_no_difference "Company.count" do
      register(valid_params(plan: "gold"))
    end

    assert_response :bad_request
    assert_equal I18n.t("errors.subscription.invalid_plan", locale: :es),
                 response.parsed_body["error"]["details"]
  end

  test "billing_cycle inválido: 400" do
    assert_no_difference "Company.count" do
      register(valid_params(billing_cycle: "weekly"))
    end

    assert_response :bad_request
  end

  test "slug repetido: agrega sufijo numérico" do
    Company.create!(name: "Café Ana", slug: "cafe-ana")
    Company.create!(name: "Café Ana 2", slug: "cafe-ana-2")

    register

    assert_response :created
    company = User.find_by!(email: "ana@ejemplo.com").companies.first
    assert_equal "cafe-ana-3", company.slug
  end

  test "es pública: no exige Authorization ni X-Company-Id" do
    register

    assert_response :created
  end

  test "429 al sexto intento desde la misma IP con el formato de ApiErrors" do
    5.times do |i|
      register(valid_params(email: "intento#{i}@ejemplo.com", company_name: "Empresa #{i}"))
      assert_response :created
    end

    assert_no_difference "Company.count" do
      register(valid_params(email: "sexto@ejemplo.com", company_name: "Sexta"))
    end

    assert_response :too_many_requests
    error = response.parsed_body["error"]
    assert_equal 429, error["status"]
    assert_equal I18n.t("errors.too_many_requests", locale: :es), error["message"]
    assert_nil error["details"]
  end
end
