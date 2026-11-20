# Spec 071 (US3): en producción, una sola línea JSON por petición (contracts/log-line.md) para buscarla y alertar en
# Better Stack, que la recibe por el Log Stream de Render. Va a su propio logger SIN etiquetas para que la línea sea JSON
# puro; lleva su request_id adentro. El resto de Rails.logger conserva `log_tags = [:request_id]`, y las líneas que se
# buscan a mano ([boot] secret_key_base, [jobs] jemalloc, [Demo::PurgeJob], [Monitoring::HeartbeatJob]) no cambian.
require "request_log"

Rails.application.configure do
  config.lograge.enabled = Rails.env.production?
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.logger = ActiveSupport::Logger.new($stdout)
  config.lograge.keep_original_rails_log = false
  # El health check de Render no deja línea (ya lo silencia `silence_healthcheck_path`).
  config.lograge.ignore_actions = [ "Rails::HealthController#show" ]
  config.lograge.custom_options = ->(event) { RequestLog.custom_options(event) }
end
