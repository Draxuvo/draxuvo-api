require "test_helper"

# Spec 069, research R4: firma de los avisos de Mercado Pago.
class TerminalProviders::MercadoPagoSignatureTest < ActiveSupport::TestCase
  SECRET = "secreto-de-prueba".freeze
  Sig = TerminalProviders::MercadoPago::Signature

  def headers(**args) = mp_webhook_headers(secret: SECRET, **args)

  test "acepta una firma válida y normaliza el id alfanumérico" do
    h = headers(data_id: "ord01abc")
    assert Sig.verify!(signature: h["x-signature"], request_id: h["x-request-id"], data_id: "ORD01ABC", secret: SECRET)
  end

  test "rechaza firma alterada, vieja, mal formada o sin secreto" do
    h = headers(data_id: "123")
    assert_raises(TerminalProviders::InvalidSignature) { Sig.verify!(signature: h["x-signature"], request_id: h["x-request-id"], data_id: "124", secret: SECRET) }
    old = headers(data_id: "123", ts: 1.hour.ago.to_i)
    assert_raises(TerminalProviders::InvalidSignature) { Sig.verify!(signature: old["x-signature"], request_id: old["x-request-id"], data_id: "123", secret: SECRET) }
    assert_raises(TerminalProviders::InvalidSignature) { Sig.verify!(signature: "basura", request_id: "r", data_id: "123", secret: SECRET) }
    assert_raises(TerminalProviders::InvalidSignature) { Sig.verify!(signature: h["x-signature"], request_id: h["x-request-id"], data_id: "123", secret: nil) }
  end

  test "el manifiesto sigue la plantilla de los SDK" do
    assert_equal "id:ord01;request-id:r1;ts:10;", Sig.manifest(data_id: "ORD01", request_id: "r1", ts: "10")
    assert_equal "id:123;ts:10;", Sig.manifest(data_id: "123", request_id: nil, ts: "10")
  end
end
