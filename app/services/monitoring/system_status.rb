# Estado del sistema (spec 073, US3): una foto que se arma al pedirla. Lo interno (API, base y cola de trabajos) se lee
# siempre; Better Stack y Sentry se consultan en paralelo y se guardan 1 minuto en caché para no gastar sus límites. Si
# un tercero falla después de un dato bueno, se muestra esa última copia marcada como vieja.
module Monitoring
  class SystemStatus
    DB_WARN_MS = 500
    EXTERNAL_TTL = 1.minute
    LAST_GOOD_TTL = 1.day
    EXTERNAL_DEADLINE = 6 # segundos; cada cliente ya corta a los 5 (2 de conexión + 3 de lectura)
    OK_STATES = %w[ok warn down].freeze

    SOURCES = {
      uptime: -> { BetterStackClient.call },
      errors: -> { SentryClient.call }
    }.freeze

    def self.call(sources: SOURCES, deadline: EXTERNAL_DEADLINE) = new(sources, deadline).call

    def initialize(sources, deadline)
      @sources = sources
      @deadline = deadline
    end

    def call
      external = read_external
      {
        checked_at: Time.current,
        api: api,
        database: database,
        jobs: JobsStatus.call,
        uptime: external[:uptime],
        errors: external[:errors],
        links: links
      }
    end

    private

    def api
      { state: "ok", version: ENV["RENDER_GIT_COMMIT"].presence || "local", booted_at: Draxuvo::BOOTED_AT,
        environment: ENV["SENTRY_ENVIRONMENT"].presence || Rails.env }
    end

    def database
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.connection.select_value("SELECT 1")
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      { state: latency > DB_WARN_MS ? "warn" : "ok", latency_ms: latency }
    rescue StandardError => error
      { state: "down", latency_ms: nil, reason: error.class.name }
    end

    # Los dos terceros en paralelo: el peor caso es el más lento, no la suma.
    def read_external
      futures = @sources.to_h { |name, reader| [ name, Concurrent::Promises.future { cached(name, reader) } ] }
      futures.to_h do |name, future|
        value = future.value(@deadline)
        [ name, value || with_last_good(name, { state: "unreachable", reason: "timeout", checked_at: Time.current }) ]
      end
    end

    def cached(name, reader)
      Rails.application.executor.wrap do
        Rails.cache.fetch("system_status:#{name}", expires_in: EXTERNAL_TTL) { fresh(name, reader) }
      end
    end

    def fresh(name, reader)
      result = reader.call.merge(checked_at: Time.current)
      if OK_STATES.include?(result[:state])
        Rails.cache.write("system_status:#{name}:last_good", result, expires_in: LAST_GOOD_TTL)
        return result.merge(stale: false, last_good_at: nil)
      end

      with_last_good(name, result)
    end

    # Falla un tercero: si hay una copia buena reciente se muestra marcada como vieja, con el motivo de la falla.
    # Sin token («Sin configurar») no se muestra nada viejo: es una decisión, no una falla.
    def with_last_good(name, failure)
      last_good = Rails.cache.read("system_status:#{name}:last_good") unless failure[:state] == "unconfigured"
      return failure.merge(stale: false, last_good_at: nil) unless last_good

      last_good.merge(stale: true, last_good_at: last_good[:checked_at], reason: failure[:reason],
                      failure_state: failure[:state], checked_at: failure[:checked_at])
    end

    def links
      { render: "https://dashboard.render.com", sentry: SentryClient.dashboard_url, betterstack: BetterStackClient.dashboard_url }
    end
  end
end
