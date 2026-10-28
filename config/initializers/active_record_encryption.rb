# Cifrado de atributos en reposo (`encrypts`), usado hoy por la llave de WhatsApp (spec 047).
#
# La API no tiene credenciales de Rails ni llave maestra: los secretos viajan por variables de entorno. Para no pedir
# variables nuevas, las tres llaves de ActiveRecord::Encryption se derivan de `SECRET_KEY_BASE`, que siempre existe
# (firma los JWT). Consecuencia: rotar `SECRET_KEY_BASE` deja ilegible lo que se guardó cifrado (docs/deploy.md);
# quien lo usa debe tratar `ActiveRecord::Encryption::Errors::Decryption` como «hay que capturar el secreto otra vez».
Rails.application.config.active_record.encryption.tap do |encryption|
  generator = Rails.application.key_generator

  encryption.primary_key = generator.generate_key("active_record_encryption/primary_key", 32).unpack1("H*")
  encryption.deterministic_key = generator.generate_key("active_record_encryption/deterministic_key", 32).unpack1("H*")
  encryption.key_derivation_salt = generator.generate_key("active_record_encryption/key_derivation_salt", 32).unpack1("H*")
end
