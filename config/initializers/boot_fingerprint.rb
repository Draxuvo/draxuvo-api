# Spec 064: la API y el worker de trabajos (draxuvo-jobs) escriben al arrancar una huella de SECRET_KEY_BASE. Si no
# coinciden en los logs, uno de los dos tiene otra llave: sesiones cerradas y la llave de WhatsApp ilegible.
# No corre en assets:precompile (SECRET_KEY_BASE_DUMMY), igual que RequiredEnv. La condición va dentro del bloque porque
# este archivo carga antes que required_env.rb.
Rails.application.config.after_initialize do
  Rails.logger.info(BootFingerprint.log_line(Rails.application.secret_key_base)) if RequiredEnv.enforce?
end
