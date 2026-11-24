# Errores para el estado del sistema (spec 073, research R12): problemas sin resolver con actividad en las últimas 24 h de
# los cuatro proyectos de Sentry, con UNA petición a la organización. El token (SENTRY_API_TOKEN) es de una integración
# interna con permisos de solo lectura; los tokens de organización no pueden leer problemas.
module Monitoring
  class SentryClient < ExternalSource
    PROJECTS = %w[draxuvo-api draxuvo-ui draxuvo-web draxuvo-app].freeze
    LIMIT = 100
    SHOWN = 5

    def self.call(http: nil) = new(token: ENV["SENTRY_API_TOKEN"], http: http).call

    def self.org = ENV.fetch("SENTRY_ORG", "draxuvo")

    def self.region_url = ENV.fetch("SENTRY_REGION_URL", "https://us.sentry.io").chomp("/")

    def self.dashboard_url = "https://#{org}.sentry.io/issues/"

    private

    def fetch
      issues = get_json("#{self.class.region_url}/api/0/organizations/#{self.class.org}/issues/",
                        query: "is:unresolved", statsPeriod: "24h", sort: "date", limit: LIMIT, project: -1)
      capped = issues.size >= LIMIT
      by_project = issues.group_by { |issue| issue.dig("project", "slug") }
      projects = PROJECTS.map do |slug|
        list = by_project.fetch(slug, [])
        { slug: slug, unresolved: list.size, capped: capped, issues: list.first(SHOWN).map { |issue| summarize(issue) } }
      end
      { state: projects.any? { |project| project[:unresolved].positive? } ? "warn" : "ok", reason: nil, projects: projects }
    end

    def summarize(issue)
      { title: issue["title"], count: issue["count"].to_i, last_seen: issue["lastSeen"], link: issue["permalink"] }
    end
  end
end
