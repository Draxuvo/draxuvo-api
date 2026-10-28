require "test_helper"

# Spec 047: la llave de WhatsApp se guarda cifrada con llaves derivadas de SECRET_KEY_BASE.
class WhatsappEncryptionTest < ActiveSupport::TestCase
  test "a value encrypted with the derived keys round-trips and the stored text hides it" do
    secret = "EAAGm0PX4ZCpsBAJ-secreto-largo"
    stored = ActiveRecord::Encryption.encryptor.encrypt(secret)

    assert_not_includes stored, secret
    assert_equal secret, ActiveRecord::Encryption.encryptor.decrypt(stored)
  end

  test "the same value encrypted twice gives different text (not deterministic)" do
    first = ActiveRecord::Encryption.encryptor.encrypt("igual")
    second = ActiveRecord::Encryption.encryptor.encrypt("igual")
    assert_not_equal first, second
  end

  test "the keys come from SECRET_KEY_BASE: another base cannot read the value" do
    stored = ActiveRecord::Encryption.encryptor.encrypt("valor")
    other = ActiveRecord::Encryption::Encryptor.new

    # Con las llaves actuales sí se lee; con una configuración distinta no.
    assert_equal "valor", ActiveRecord::Encryption.encryptor.decrypt(stored)
    ActiveRecord::Encryption.with_encryption_context(key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("otra-llave")) do
      assert_raises(ActiveRecord::Encryption::Errors::Decryption) { other.decrypt(stored, key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("otra-llave")) }
    end
  end

  test "access_token and token parameters are filtered from the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("access_token" => "EAAG123", "token" => "abc", "phone_number_id" => "104512345678901")

    assert_equal "[FILTERED]", filtered["access_token"]
    assert_equal "[FILTERED]", filtered["token"]
    assert_equal "104512345678901", filtered["phone_number_id"]
  end
end
