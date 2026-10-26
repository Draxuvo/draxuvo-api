# Spec 039: límites de la demo, leídos de las variables de entorno al momento de usarse (así las pruebas y el CI
# pueden cambiarlas). Vive en app/ y no en un initializer para que Zeitwerk maneje el espacio de nombres Demo.
module Demo
  module Config
    module_function

    # Aperturas por IP y hora (rate_limit del controlador).
    def rate_limit = Integer(ENV.fetch("DEMO_RATE_LIMIT", 10))

    # Demos activas a la vez; al llegar al tope se responde 503 demo_busy.
    def max_active = Integer(ENV.fetch("DEMO_MAX_ACTIVE", 150))

    # Aprovisionamientos simultáneos (ranuras con pg_try_advisory_lock).
    def max_provisioning = Integer(ENV.fetch("DEMO_MAX_PROVISIONING", 2))

    # Vigencia de una demo.
    def ttl = Integer(ENV.fetch("DEMO_TTL_MINUTES", 120)).minutes

    # Vigencia por defecto de una invitación del equipo comercial.
    def invite_days = Integer(ENV.fetch("DEMO_INVITE_DAYS", 14))
  end
end
