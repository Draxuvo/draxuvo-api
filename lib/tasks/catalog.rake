namespace :catalog do
  # bin/rails "catalog:load[db/catalogs/aqui_me_quedo.yml]"          (dueño del YAML)
  # bin/rails "catalog:load[db/catalogs/aqui_me_quedo.yml,otro@correo.com]"
  desc "Carga estaciones, mesas, terminales y productos de un negocio desde un YAML"
  task :load, %i[file owner_email] => :environment do |_task, args|
    data = YAML.safe_load_file(args.fetch(:file))
    result = Catalogs::Loader.call(data, owner_email: args[:owner_email])
    puts "Empresa: #{result.company.name} (id #{result.company.id})"
    puts "Creados: #{result.created.to_h}"
    puts "Actualizados: #{result.updated.to_h}"
    result.warnings.each { |warning| puts "Aviso: #{warning}" }
  end
end
