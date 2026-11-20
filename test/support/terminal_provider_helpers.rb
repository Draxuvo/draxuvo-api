# Ayudantes de la terminal integrada (spec 069). Nunca se llama a Mercado Pago en pruebas: `with_fake_provider` reemplaza
# `TerminalProviders.for` por un proveedor falso cuyas respuestas se fijan por prueba y que registra cada llamada.
module TerminalProviderHelpers
  class FakeProvider < TerminalProviders::Base
    attr_reader :calls
    attr_accessor :devices_list, :charge_status, :charge_detail, :create_error, :fetch_error, :cancel_result,
                  :refund_result, :refund_error, :prepare_result, :prepare_error, :credentials, :exchange_error,
                  :refresh_error, :devices_error, :notice, :available, :reference, :card_last4

    def initialize
      @calls = []
      @devices_list = [ TerminalProviders::Device.new(id: "NEWLAND_N950__SERIAL0001", label: "NEWLAND N950 · …0001", mode: "STANDALONE") ]
      @charge_status = "pending"
      @charge_detail = "at_terminal"
      @cancel_result = :canceled
      @refund_result = TerminalProviders::ProviderRefund.new(id: "REF01", status: "done")
      @prepare_result = TerminalProviders::Preparation.new(mode: "PDV", restart_required: true)
      @credentials = TerminalProviders::Credentials.new(access_token: "APP_USR-token", refresh_token: "TG-refresh",
                                                        expires_at: 180.days.from_now, account_id: "1001",
                                                        account_label: "Cuenta de prueba", live_mode: true)
      @available = true
      @reference = "123456789"
      @card_last4 = "4242"
    end

    def provider = "mercado_pago"
    def available? = @available

    def authorize_url(state:, code_challenge:)
      record(:authorize_url, state: state, code_challenge: code_challenge)
      "https://auth.example.test/authorization?state=#{state}"
    end

    def exchange_code(code:, code_verifier:)
      record(:exchange_code, code: code, code_verifier: code_verifier)
      raise_error(@exchange_error)
      @credentials
    end

    def refresh(connection)
      record(:refresh, connection_id: connection.id)
      raise_error(@refresh_error)
      @credentials
    end

    def devices(connection, limit:, offset:)
      record(:devices, connection_id: connection.id, limit: limit, offset: offset)
      raise_error(@devices_error)
      [ @devices_list.drop(offset).first(limit), @devices_list.size ]
    end

    def prepare_device(connection, device_id)
      record(:prepare_device, device_id: device_id)
      raise_error(@prepare_error)
      @prepare_result
    end

    def create_charge(charge)
      record(:create_charge, charge_id: charge.id, amount: charge.amount, idempotency_key: charge.idempotency_key)
      raise_error(@create_error)
      TerminalProviders::ProviderCharge.new(id: "ORD#{charge.id}", payment_id: "PAY#{charge.id}", status: "pending", detail: "created")
    end

    def fetch_charge(charge)
      record(:fetch_charge, charge_id: charge.id)
      raise_error(@fetch_error)
      approved = @charge_status == "approved"
      TerminalProviders::ProviderCharge.new(id: charge.provider_order_id, payment_id: charge.provider_payment_id,
                                            status: @charge_status, detail: @charge_detail,
                                            reference: (approved ? @reference : nil), card_last4: (approved ? @card_last4 : nil),
                                            payment_type: (approved ? "credit_card" : nil))
    end

    def cancel_charge(charge)
      record(:cancel_charge, charge_id: charge.id)
      @cancel_result.is_a?(Exception) ? raise(@cancel_result) : @cancel_result
    end

    def refund(charge, idempotency_key:)
      record(:refund, charge_id: charge.id, idempotency_key: idempotency_key)
      raise_error(@refund_error)
      @refund_result
    end

    def parse_webhook(body:, headers:, params:)
      record(:parse_webhook, params: params)
      raise TerminalProviders::InvalidSignature, "mismatch" if headers["x-signature"] == "bad"

      @notice
    end

    def calls_of(name) = @calls.select { |call| call[:name] == name }

    private

    def record(name, **data) = @calls << data.merge(name: name)

    def raise_error(error)
      raise error if error
    end
  end

  def provider_error(family, reason = "error", http_status: nil)
    TerminalProviders::Error.new(TerminalProviders::Failure.new(family: family, reason: reason.to_s, http_status: http_status))
  end

  # Reemplaza el proveedor dentro del bloque y devuelve el falso (para revisar sus llamadas).
  def with_fake_provider(fake = FakeProvider.new)
    TerminalProviders.stub(:for, fake) { yield fake }
    fake
  end

  # Conexión de Mercado Pago lista para usar.
  def terminal_connection_for(company, status: "connected", account_id: "1001")
    TerminalConnection.find_or_create_by!(company: company, provider: "mercado_pago") do |connection|
      connection.status = status
      connection.account_id = account_id
      connection.account_label = "Cuenta de prueba"
      connection.access_token = "APP_USR-token"
      connection.refresh_token = "TG-refresh"
      connection.token_expires_at = 180.days.from_now
      connection.connected_at = Time.current
    end
  end

  @@device_seq = 0

  # Terminal integrada y activa de la empresa.
  def integrated_terminal(company, name: "Caja integrada", connection: nil)
    @@device_seq += 1
    connection ||= terminal_connection_for(company)
    company.payment_terminals.create!(name: "#{name} #{@@device_seq}", provider: "mercado_pago", terminal_connection: connection,
                                      device_id: "NEWLAND_N950__T#{Process.pid}#{@@device_seq}", device_mode: "PDV")
  end

  # Encabezados de un aviso de Mercado Pago firmado como lo firma la plataforma (research R4).
  def mp_webhook_headers(data_id:, secret:, request_id: "req-#{SecureRandom.hex(4)}", ts: Time.current.to_i)
    manifest = TerminalProviders::MercadoPago::Signature.manifest(data_id: data_id, request_id: request_id, ts: ts)
    { "x-signature" => "ts=#{ts},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, manifest)}", "x-request-id" => request_id }
  end
end

ActiveSupport::TestCase.include TerminalProviderHelpers
