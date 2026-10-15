# Fija variables de ENV dentro del bloque (nil la elimina) y restaura los valores previos.
module EnvHelpers
  def with_env(vars)
    vars = vars.transform_keys(&:to_s)
    previous = vars.keys.to_h { |key| [ key, ENV.key?(key) ? ENV[key] : :unset ] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value.to_s }
    yield
  ensure
    previous&.each { |key, value| value == :unset ? ENV.delete(key) : ENV[key] = value }
  end
end
