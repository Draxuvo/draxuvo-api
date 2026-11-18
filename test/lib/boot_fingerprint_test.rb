require "test_helper"

# Spec 064: la API y el worker escriben al arrancar una huella de SECRET_KEY_BASE para comprobar que usan la misma llave
# sin exponerla.
class BootFingerprintTest < ActiveSupport::TestCase
  SECRET = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" * 2

  test "the fingerprint is exactly 8 hexadecimal characters" do
    assert_match(/\A\h{8}\z/, BootFingerprint.of(SECRET))
  end

  test "the same key gives the same fingerprint and another key a different one" do
    assert_equal BootFingerprint.of(SECRET), BootFingerprint.of(SECRET.dup)
    assert_not_equal BootFingerprint.of(SECRET), BootFingerprint.of("#{SECRET}x")
  end

  test "the fingerprint does not contain any piece of the key" do
    fingerprint = BootFingerprint.of(SECRET)
    assert_not_includes SECRET, fingerprint
    assert_equal Digest::SHA256.hexdigest(SECRET)[0, 8], fingerprint
  end

  test "an empty or missing key gives none without raising" do
    assert_equal "none", BootFingerprint.of(nil)
    assert_equal "none", BootFingerprint.of("")
    assert_equal "none", BootFingerprint.of("   ")
  end

  test "the log line names the key and the fingerprint" do
    assert_equal "[boot] secret_key_base sha256:#{BootFingerprint.of(SECRET)}", BootFingerprint.log_line(SECRET)
  end
end
