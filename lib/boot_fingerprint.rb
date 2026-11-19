# Spec 064: huella corta de SECRET_KEY_BASE para comprobar en los logs que la API y el worker usan la misma llave.
# Son los primeros 8 caracteres de su SHA-256: sirven para comparar y no dejan reconstruir la llave.
module BootFingerprint
  def self.of(secret)
    return "none" if secret.to_s.strip.empty?

    Digest::SHA256.hexdigest(secret)[0, 8]
  end

  def self.log_line(secret)
    "[boot] secret_key_base sha256:#{of(secret)}"
  end
end
