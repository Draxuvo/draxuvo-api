# Ayudantes de las pruebas de avisos push (spec 057). Expo nunca se llama de verdad: `with_fake_expo` sustituye el
# cliente y guarda los mensajes; cada mensaje responde `ok` salvo que el bloque `ticket` diga otra cosa.
module PushHelpers
  class FakeExpo
    attr_reader :messages

    def initialize(ticket: nil, raise_error: nil)
      @messages = []
      @ticket = ticket
      @raise_error = raise_error
    end

    def send_messages(messages)
      raise @raise_error if @raise_error

      @messages.concat(messages)
      messages.map.with_index { |message, i| @ticket ? @ticket.call(message, i) : { "status" => "ok", "id" => "ticket-#{SecureRandom.hex(4)}" } }
    end

    def receipts(_ids) = {}
  end

  def with_fake_expo(**options)
    fake = FakeExpo.new(**options)
    Push::ExpoClient.stub(:new, fake) { yield fake }
    fake
  end

  def register_device(user, token: "ExponentPushToken[#{SecureRandom.hex(8)}]", platform: "android", locale: "es")
    PushDevice.register!(user: user, token: token, platform: platform, locale: locale)
  end
end

ActiveSupport::TestCase.include(PushHelpers)
ActionDispatch::IntegrationTest.include(PushHelpers) if defined?(ActionDispatch::IntegrationTest)
