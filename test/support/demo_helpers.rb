# Ayudantes de las pruebas de la demo (spec 039).
module DemoHelpers
  # Tablas con filas de datos, para comparar antes y después de provisionar y purgar (cero residuo).
  def table_row_counts
    ActiveRecord::Base.connection.tables.sort.index_with do |table|
      next 0 if %w[schema_migrations ar_internal_metadata].include?(table)

      ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name(table)}").to_i
    end
  end

  # Corre el bloque con la empresa activa tratada como demo (como lo hace BaseController).
  def as_demo
    Current.demo = true
    yield
  ensure
    Current.demo = nil
  end

  def with_demo_env(vars)
    old = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value.to_s }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

ActiveSupport::TestCase.include DemoHelpers
