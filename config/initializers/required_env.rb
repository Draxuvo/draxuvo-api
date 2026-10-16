# Variables que la API necesita en producción (spec 012, FR-004).
#
# Si falta alguna, el arranque falla con un mensaje que las nombra, en vez de seguir con valores
# por defecto de otra marca (hosts, remitente, enlaces). Inventario completo, con valores
# esperados y responsables: specs/012-deploy-produccion/contracts/env-inventory.md del workspace.
#
# No se exigen aquí: SUPER_ADMIN_PASSWORD (solo la piden los seeds, db/seeds.rb) ni
# RAILS_MASTER_KEY (production.rb tiene require_master_key = false; todo viene de ENV).
module RequiredEnv
  class MissingError < StandardError; end

  NAMES = %w[
    SECRET_KEY_BASE
    DATABASE_URL
    APP_HOST
    ALLOWED_HOSTS
    FRONTEND_URL
    FRONTEND_URL_UI
    RESEND_API_KEY
    RESEND_FROM_EMAIL
    STRIPE_API_KEY
    STRIPE_WEBHOOK_SECRET
  ].freeze

  # Con ACTIVE_STORAGE_SERVICE=r2 (archivos en Cloudflare R2) se exigen también sus credenciales.
  R2_NAMES = %w[R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET].freeze

  def self.required(env = ENV)
    env["ACTIVE_STORAGE_SERVICE"].to_s == "r2" ? NAMES + R2_NAMES : NAMES
  end

  def self.missing(env = ENV)
    required(env).select { |name| env[name].to_s.strip.empty? }
  end

  def self.check!(env = ENV)
    absent = missing(env)
    return if absent.empty?

    raise MissingError, "Faltan variables de entorno obligatorias en producción: #{absent.join(', ')}"
  end

  # `assets:precompile` del Dockerfile corre en producción con SECRET_KEY_BASE_DUMMY y sin el resto
  # de las variables: ahí no se valida.
  def self.enforce?(rails_env = Rails.env, env = ENV)
    rails_env.to_s == "production" && env["SECRET_KEY_BASE_DUMMY"].to_s.empty?
  end
end

RequiredEnv.check! if RequiredEnv.enforce?
