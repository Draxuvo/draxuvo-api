# Spec 071: errores no controlados de la API y de los trabajos en segundo plano a Sentry. Sin SENTRY_DSN (desarrollo,
# pruebas, CI) no se inicializa y `Sentry.capture_exception` no hace nada. Guía: docs/monitoreo.md.
#
# Privacidad (contracts/error-event.md): solo el id del usuario; sin cuerpos, cookies, encabezados, query string ni
# argumentos de trabajos. `data_collection` (sentry-ruby 7) apaga lo que junta el SDK y SentryScrubber limpia el resto.
# Memoria (la API corre en 512 MB): sin tracing ni profiling salvo que SENTRY_TRACES_SAMPLE_RATE diga otra cosa.
require "sentry_scrubber"

if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)
    # Render define RENDER_GIT_COMMIT con el commit desplegado (el Deploy Hook manda ref=GITHUB_SHA).
    config.release = ENV["RENDER_GIT_COMMIT"].presence
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0").to_f

    data = config.data_collection
    data.user_info = false
    data.cookies = false
    data.http_headers.request = Sentry::DataCollection::KeyValueCollection.new(mode: :allow_list, terms: [ "User-Agent" ])
    data.http_headers.response = false
    data.http_bodies = []
    data.url_query_params = false
    data.database_query_data = false
    data.queues = false
    data.stack_frame_variables = false

    # Los 4xx esperados no son errores del servidor. ErrorHandler ya no los deja llegar al middleware; esto cubre los
    # que se reporten por otro camino (trabajos, el reportero de errores de Rails).
    config.excluded_exceptions += %w[
      ApiErrors::BaseError
      Demo::Restricted
      Pagy::VariableError
      ActiveRecord::StaleObjectError
      ActiveModel::RangeError
      ActiveRecord::RangeError
      JWT::DecodeError
    ]

    config.before_send = ->(event, hint) { SentryScrubber.call(event, hint) }

    # Un trabajo con reintentos se reporta una sola vez, al agotarlos.
    config.rails.active_job_report_on_retry_error = false
  end
end
