# Spec 064: la misma espera que hace bin/jobs al arrancar en producción, para correrla a mano.
namespace :db do
  desc "Espera a que no haya migraciones pendientes (tope: MIGRATION_WAIT_SECONDS, 600 s por omisión)"
  task wait_for_migrations: :environment do
    exit 1 unless MigrationWait.for_database(logger: Logger.new($stdout)).call
  end
end
