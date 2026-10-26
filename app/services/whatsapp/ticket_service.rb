require "net/http"
require "json"

module Whatsapp
  class TicketService
    GRAPH_API_VERSION = "v25.0"
    GRAPH_BASE        = "https://graph.facebook.com"

    def initialize(ticket, phone:)
      @ticket = ticket
      @phone  = sanitize_phone(phone)
    end

    # Intenta enviar el PDF como documento.
    # Si falla por ventana de 24h (código 131026/131047), envía texto como fallback.
    def call
      # Spec 039: una demo no manda WhatsApp reales.
      return { "demo" => true } if Demo::Guard.active?

      log(:info, "START ticket_id=#{@ticket.id} folio=#{@ticket.folio} phone=#{@phone}")
      validate_config!

      log(:info, "generating PDF ticket_id=#{@ticket.id}")
      pdf = Pdf::TicketPdfService.new(@ticket).generate
      log(:info, "PDF generated size=#{pdf.bytesize} bytes")

      media_id = upload_media(pdf)
      result   = send_document(media_id)

      log(:info, "SUCCESS message_id=#{result.dig('messages', 0, 'id')} to=#{@phone}")
      result
    rescue ConversationWindowError => e
      log(:warn, "24h window closed, falling back to text message: #{e.message}")
      result = send_text_fallback
      log(:info, "FALLBACK SUCCESS message_id=#{result.dig('messages', 0, 'id')} to=#{@phone}")
      result
    end

    private

    # Error interno para detectar ventana de 24h cerrada
    class ConversationWindowError < StandardError; end

    def upload_media(pdf_bytes)
      boundary = "WhatsApp#{SecureRandom.hex(10)}"
      body     = multipart_body(pdf_bytes, boundary)

      log(:info, "uploading media phone_number_id=#{phone_number_id} body_size=#{body.bytesize} bytes")

      result = request(
        path:         "/#{phone_number_id}/media",
        body:         body,
        content_type: "multipart/form-data; boundary=#{boundary}"
      )

      media_id = result.fetch("id")
      log(:info, "media uploaded media_id=#{media_id}")
      media_id
    end

    def send_document(media_id)
      payload = {
        messaging_product: "whatsapp",
        to:                @phone,
        type:              "document",
        document: {
          id:       media_id,
          filename: "ticket-#{@ticket.folio}.pdf",
          caption:  ticket_caption
        }
      }

      log(:info, "sending document to=#{@phone} media_id=#{media_id} filename=ticket-#{@ticket.folio}.pdf")

      request(
        path:         "/#{phone_number_id}/messages",
        body:         payload.to_json,
        content_type: "application/json"
      )
    end

    # Mensaje de texto con los datos del ticket cuando no hay ventana de 24h abierta.
    def send_text_fallback
      order = @ticket.work_order
      lines = order ? order.work_order_items.map { |i| [ i.description, i.quantity, i.subtotal ] } : check_lines
      items = lines.map { |description, quantity, subtotal| "  • #{description} x#{quantity} — $#{format('%.2f', subtotal)}" }.join("\n")
      subject = order ? order.title : check_subject

      body = <<~MSG.strip
        🧾 *Ticket #{@ticket.folio}*
        #{order ? 'Orden' : 'Cuenta'}: #{subject}
        Estado: #{@ticket.status_label_text}
        Fecha: #{@ticket.created_at.strftime('%d/%m/%Y')}

        #{items.presence || '  (sin detalle de items)'}

        *Total: $#{format('%.2f', @ticket.total)} MXN*

        Para descargar el PDF ingresa a tu portal o contacta al negocio.
      MSG

      payload = {
        messaging_product: "whatsapp",
        to:                @phone,
        type:              "text",
        text:              { body: body }
      }

      log(:info, "sending text fallback to=#{@phone}")

      request(
        path:         "/#{phone_number_id}/messages",
        body:         payload.to_json,
        content_type: "application/json"
      )
    end

    def request(path:, body:, content_type:)
      uri = URI("#{GRAPH_BASE}/#{GRAPH_API_VERSION}#{path}")
      log(:info, "POST #{uri}")

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 30

      req                  = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"]  = content_type
      req.body             = body

      res  = http.request(req)
      data = JSON.parse(res.body)

      log(:info, "response HTTP=#{res.code} body=#{data.to_json}")

      unless res.is_a?(Net::HTTPSuccess)
        error_code = data.dig("error", "code")
        msg        = data.dig("error", "message") || "WhatsApp API error (HTTP #{res.code})"
        log(:error, "API error code=#{res.code} error_code=#{error_code} message=#{msg}")

        # 131026 = recipient not in window, 131047 = business-initiated outside template
        raise ConversationWindowError, msg if error_code.to_i.in?([ 131026, 131047 ])

        raise ApiErrors::UnprocessableEntityError.new(details: msg)
      end

      data
    end

    def multipart_body(pdf_bytes, boundary)
      crlf = "\r\n"
      "".b.tap do |b|
        b << "--#{boundary}#{crlf}".b
        b << "Content-Disposition: form-data; name=\"messaging_product\"#{crlf}#{crlf}".b
        b << "whatsapp#{crlf}".b
        b << "--#{boundary}#{crlf}".b
        b << "Content-Disposition: form-data; name=\"file\"; filename=\"ticket.pdf\"#{crlf}".b
        b << "Content-Type: application/pdf#{crlf}#{crlf}".b
        b << pdf_bytes
        b << "#{crlf}--#{boundary}--#{crlf}".b
      end
    end

    def ticket_caption
      "Ticket #{@ticket.folio} — Total: $#{format('%.2f', @ticket.total)} MXN"
    end

    def sanitize_phone(phone)
      phone.to_s.gsub(/\D/, "")
    end

    def validate_config!
      missing = []
      missing << "WHATSAPP_ACCESS_TOKEN"   unless ENV["WHATSAPP_ACCESS_TOKEN"].present?
      missing << "WHATSAPP_PHONE_NUMBER_ID" unless ENV["WHATSAPP_PHONE_NUMBER_ID"].present?
      return if missing.empty?

      # WhatsApp está desactivado en el lanzamiento (spec 012): al cliente solo se le dice que no está
      # disponible; los nombres de las variables van al log, no a la respuesta.
      log(:warn, "WhatsApp no configurado, faltan: #{missing.join(', ')}")
      raise ApiErrors::UnprocessableEntityError.new(details: I18n.t("whatsapp.not_configured"))
    end

    def check_lines
      @ticket.check.check_items.counted.order(:id).map { |i| [ i.name, i.quantity, i.subtotal ] }
    end

    def check_subject
      check = @ticket.check
      check.dining_table ? "Mesa #{check.dining_table.name}" : "Para llevar: #{check.takeout_name}"
    end

    def log(level, msg)
      tagged = "[WhatsApp::TicketService] #{msg}"
      Rails.logger.public_send(level, tagged)
    end

    def phone_number_id
      ENV["WHATSAPP_PHONE_NUMBER_ID"]
    end

    def access_token
      ENV["WHATSAPP_ACCESS_TOKEN"]
    end
  end
end
