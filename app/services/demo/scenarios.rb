# Spec 039: escenarios de datos de la demo, uno por plan y giro. Cada uno es determinista (mismos nombres y cifras en
# cada visita; solo las fechas son relativas a hoy) para que la demo se vea siempre completa y, más adelante, para que
# el recorrido automático que grabe los videos sea reproducible.
module Demo
  module Scenarios
    PLAN_OF = {
      "basic_retail" => "basic",
      "pro_service" => "pro",
      "pro_restaurant" => "pro",
      "enterprise_restaurant" => "enterprise"
    }.freeze

    module_function

    def keys = PLAN_OF.keys

    def plan_of(key) = PLAN_OF[key.to_s]

    # Escenarios de un plan; en Pro hay dos (servicio técnico y restaurante).
    def for_plan(plan) = PLAN_OF.select { |_key, value| value == plan.to_s }.keys

    def valid?(plan, scenario) = PLAN_OF[scenario.to_s] == plan.to_s

    def fetch(key)
      raise KeyError, "escenario desconocido: #{key.inspect}" unless PLAN_OF.key?(key.to_s)

      const_get(key.to_s.camelize)
    end
  end
end
