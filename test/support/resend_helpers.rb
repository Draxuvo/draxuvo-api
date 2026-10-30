# Respuesta como la entrega la gema `resend`: un HTTParty::Response con las claves en símbolo (`{ id: "…" }`),
# no un Hash de claves de texto. Las pruebas que simulaban `{ "id" => … }` no veían los fallos con la respuesta real.
module ResendHelpers
  def resend_response(body = { id: "email_1" })
    http_response = Net::HTTPOK.new("1.1", "200", "OK")
    http_response.instance_variable_set(:@read, true)
    http_response.instance_variable_set(:@body, body.to_json)
    request = HTTParty::Request.new(Net::HTTP::Post, "https://api.resend.com/emails")
    HTTParty::Response.new(request, http_response, -> { body })
  end
end
