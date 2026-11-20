module TerminalConnections
  # Renueva cada día los tokens a los que les quedan menos de 30 días (spec 069, research R2). El proveedor devuelve un
  # refresh token nuevo en cada renovación: se guarda siempre el último. Un fallo de conexión deja la conexión «Con error»
  # y avisa; uno pasajero se reintenta al día siguiente.
  class RefreshJob < ApplicationJob
    queue_as :default

    WINDOW = 30.days

    def perform
      TerminalConnection.connected.where("token_expires_at IS NULL OR token_expires_at < ?", WINDOW.from_now).find_each do |connection|
        refresh(connection)
      end
    end

    private

    def refresh(connection)
      credentials = TerminalProviders.for(connection.provider).refresh(connection)
      connection.store_credentials!(credentials)
      TerminalEvent.log!(:token_refreshed, connection: connection)
    rescue TerminalProviders::Error => e
      Health.failed!(connection, e.failure) if e.failure.connection? || e.failure.reason == "invalid_grant"
      Rails.logger.warn("[TerminalConnections::RefreshJob] connection=#{connection.id} #{e.failure.family} #{e.failure.reason}")
    end
  end
end
