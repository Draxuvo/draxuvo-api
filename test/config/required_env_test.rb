require "test_helper"

# FR-004 (spec 012): en producción la API no arranca sin las variables obligatorias, para no
# caer en valores por defecto de otra marca (hosts, remitente, enlaces).
class RequiredEnvTest < ActiveSupport::TestCase
  COMPLETE = {
    "SECRET_KEY_BASE" => "x" * 64,
    "DATABASE_URL" => "postgres://user:pass@db.example.com/draxuvo",
    "APP_HOST" => "api.draxuvo.com",
    "ALLOWED_HOSTS" => "api.draxuvo.com",
    "FRONTEND_URL" => "https://app.draxuvo.com",
    "FRONTEND_URL_UI" => "https://draxuvo.com",
    "RESEND_API_KEY" => "re_test",
    "RESEND_FROM_EMAIL" => "Draxuvo <no-reply@draxuvo.com>",
    "STRIPE_API_KEY" => "sk_test_x",
    "STRIPE_WEBHOOK_SECRET" => "whsec_x"
  }.freeze

  test "con todas las variables no falta ninguna" do
    assert_empty RequiredEnv.missing(COMPLETE)
    assert_nothing_raised { RequiredEnv.check!(COMPLETE) }
  end

  test "cada variable obligatoria ausente se reporta por nombre" do
    COMPLETE.each_key do |name|
      env = COMPLETE.except(name)
      assert_equal [ name ], RequiredEnv.missing(env), "debía faltar solo #{name}"
      error = assert_raises(RequiredEnv::MissingError) { RequiredEnv.check!(env) }
      assert_includes error.message, name
    end
  end

  test "una variable vacía o con solo espacios cuenta como ausente" do
    assert_equal %w[APP_HOST ALLOWED_HOSTS], RequiredEnv.missing(COMPLETE.merge("APP_HOST" => "", "ALLOWED_HOSTS" => "  "))
  end

  test "el mensaje lista todas las que faltan" do
    error = assert_raises(RequiredEnv::MissingError) { RequiredEnv.check!({}) }
    COMPLETE.each_key { |name| assert_includes error.message, name }
  end

  test "SUPER_ADMIN_PASSWORD y RAILS_MASTER_KEY no se exigen al arrancar" do
    assert_not_includes RequiredEnv::NAMES, "SUPER_ADMIN_PASSWORD"
    assert_not_includes RequiredEnv::NAMES, "RAILS_MASTER_KEY"
  end

  test "solo se valida en producción y no durante la precompilación de assets" do
    assert RequiredEnv.enforce?("production", {})
    assert_not RequiredEnv.enforce?("development", {})
    assert_not RequiredEnv.enforce?("test", {})
    assert_not RequiredEnv.enforce?("production", { "SECRET_KEY_BASE_DUMMY" => "1" })
  end

  # Archivos subidos: el disco del contenedor es efímero, así que producción los guarda en
  # Cloudflare R2 (ACTIVE_STORAGE_SERVICE=r2) y entonces exige sus credenciales.
  R2 = {
    "ACTIVE_STORAGE_SERVICE" => "r2",
    "R2_ACCOUNT_ID" => "0123456789abcdef0123456789abcdef",
    "R2_ACCESS_KEY_ID" => "akid",
    "R2_SECRET_ACCESS_KEY" => "secret",
    "R2_BUCKET" => "draxuvo-uploads"
  }.freeze

  test "con el servicio r2 se exigen sus credenciales" do
    assert_equal %w[R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET],
                 RequiredEnv.missing(COMPLETE.merge("ACTIVE_STORAGE_SERVICE" => "r2"))
    assert_empty RequiredEnv.missing(COMPLETE.merge(R2))
  end

  test "sin servicio r2 no se piden credenciales de R2" do
    assert_empty RequiredEnv.missing(COMPLETE)
    assert_empty RequiredEnv.missing(COMPLETE.merge("ACTIVE_STORAGE_SERVICE" => "local"))
  end

  test "el servicio r2 de storage.yml se construye contra el endpoint de R2" do
    # storage.yml se evalúa una vez al arrancar Rails: aquí se lee de nuevo con las variables del bloque.
    with_env(R2.except("ACTIVE_STORAGE_SERVICE")) do
      yaml = ERB.new(Rails.root.join("config/storage.yml").read).result
      configurations = YAML.safe_load(yaml, aliases: true).deep_symbolize_keys
      service = ActiveStorage::Service.configure(:r2, configurations)
      assert_instance_of ActiveStorage::Service::S3Service, service
      assert_equal "draxuvo-uploads", service.bucket.name
      assert_equal "https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com",
                   service.client.client.config.endpoint.to_s
    end
  end
end
