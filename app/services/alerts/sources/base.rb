module Alerts
  module Sources
    # Una fuente produce las alertas de un tipo para una empresa. `module_key` es el módulo del plan que la habilita.
    class Base
      def self.module_key = raise(NotImplementedError)

      def initialize(company, thresholds, now)
        @company = company
        @thresholds = thresholds
        @now = now
      end

      def call = raise(NotImplementedError)

      private

      attr_reader :company, :thresholds, :now

      def over?(since, limit_minutes) = since.present? && (now - since) > limit_minutes * 60

      def elapsed_minutes(since) = ((now - since) / 60).floor

      # Crítica cuando lleva el doble del límite.
      def severity_for(minutes, limit_minutes) = minutes >= limit_minutes * 2 ? "critical" : "warning"
    end
  end
end
