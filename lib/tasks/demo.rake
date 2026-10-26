# Spec 039: gate de rendimiento de la demo (R10). Provisiona y purga cada escenario y mide cuánto tarda; el objetivo
# es 5 s o menos por escenario. Úsala contra una base de desarrollo, nunca contra producción.
namespace :demo do
  desc "Mide cuánto tarda aprovisionar cada escenario de la demo (objetivo: 5 s o menos)"
  task benchmark: :environment do
    abort("demo:benchmark es solo para desarrollo o pruebas") if Rails.env.production?

    budget = 5.0
    over = []
    Demo::Scenarios.keys.each do |key|
      result = nil
      seconds = Benchmark.realtime { result = Demo::Provision.call(plan: Demo::Scenarios.plan_of(key), scenario: key, locale: "es") }
      purge = Benchmark.realtime { Demo::Purge.call(result.company) }
      puts format("%-24s aprovisionar %.2f s · purgar %.2f s%s", key, seconds, purge, seconds > budget ? "  <-- pasa de #{budget} s" : "")
      over << key if seconds > budget
    end
    abort("Escenarios fuera de presupuesto: #{over.join(', ')}") if over.any?
    puts "Todos dentro de #{budget} s."
  end
end
