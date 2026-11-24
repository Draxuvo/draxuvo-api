# Disponibilidad para el estado del sistema (spec 073, research R11): monitores y latidos de Better Stack Uptime, con un
# token de solo lectura en BETTERSTACK_UPTIME_TOKEN. Dos peticiones por lectura; la copia en caché vive en SystemStatus.
module Monitoring
  class BetterStackClient < ExternalSource
    BASE_URL = "https://uptime.betterstack.com/api/v2".freeze
    DOWN = %w[down].freeze
    ATTENTION = %w[paused pending maintenance validating].freeze

    def self.call(http: nil) = new(token: ENV["BETTERSTACK_UPTIME_TOKEN"], http: http).call

    def self.team = ENV.fetch("BETTERSTACK_TEAM_ID", "t641548")

    def self.dashboard_url = "https://uptime.betterstack.com/team/#{team}/monitors"

    private

    def fetch
      monitors = get_json("#{BASE_URL}/monitors", per_page: 50).fetch("data", []).map { |row| monitor(row) }
      heartbeats = get_json("#{BASE_URL}/heartbeats", per_page: 50).fetch("data", []).map { |row| heartbeat(row) }
      statuses = (monitors + heartbeats).map { |item| item[:status] }
      { state: overall(statuses), reason: nil, monitors: monitors, heartbeats: heartbeats }
    end

    def monitor(row)
      attrs = row.fetch("attributes", {})
      { name: attrs["pronounceable_name"].presence || attrs["url"], url: attrs["url"], status: attrs["status"],
        last_checked_at: attrs["last_checked_at"], link: "https://uptime.betterstack.com/team/#{self.class.team}/monitors/#{row['id']}" }
    end

    def heartbeat(row)
      attrs = row.fetch("attributes", {})
      { name: attrs["name"], status: attrs["status"],
        link: "https://uptime.betterstack.com/team/#{self.class.team}/heartbeats/#{row['id']}" }
    end

    def overall(statuses)
      return "down" if statuses.intersect?(DOWN)
      return "warn" if statuses.intersect?(ATTENTION)

      "ok"
    end
  end
end
