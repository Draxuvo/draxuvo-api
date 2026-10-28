module Whatsapp
  class TicketService
    # Subir el PDF puede tardar más que una consulta normal.
    UPLOAD_READ_TIMEOUT = 30

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

    # Spec 047: la configuración sale de `Whatsapp::Config` (panel primero, variables de entorno de respaldo).
    def config = @config ||= Whatsapp::Config.current

    def upload_media(pdf_bytes)
      log(:info, "uploading media phone_number_id=#{phone_number_id} body_size=#{pdf_bytes.bytesize} bytes")

      result = config.client(read_timeout: UPLOAD_READ_TIMEOUT).post_multipart(
        "/#{phone_number_id}/media",
        fields: { messaging_product: "whatsapp" },
        file: { filename: "ticket.pdf", content_type: "application/pdf", bytes: pdf_bytes }
      )

      media_id = check!(result).fetch("id")
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

      post_message(payload)
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

      post_message(payload)
    end

    def post_message(payload)
      data = check!(config.client.post("/#{phone_number_id}/messages", payload))
      Whatsapp::Health.record_success(:ticket)
      data
    end

    # Devuelve los datos de una respuesta correcta; ante un fallo lo reporta a `Whatsapp::Health` (si es de la conexión o
    # de la plantilla) y lanza el error de siempre.
    def check!(result)
      return result.data if result.ok?

      failure = result.failure
      log(:error, "API error code=#{failure.code} family=#{failure.family}")

      # 131026 = destinatario fuera de ventana, 131047 = mensaje iniciado por el negocio sin plantilla: se cae a texto
      raise ConversationWindowError, failure.user_message if failure.code.to_i.in?([ 131026, 131047 ])

      Whatsapp::Health.record_failure(:ticket, failure)
      raise ApiErrors::UnprocessableEntityError.new(details: failure.user_message)
    end

    def ticket_caption
      "Ticket #{@ticket.folio} — Total: $#{format('%.2f', @ticket.total)} MXN"
    end

    def sanitize_phone(phone)
      phone.to_s.gsub(/\D/, "")
    end

    # Canal apagado, sin conexión o sin configurar: al cliente solo se le dice que no está disponible; el motivo va al log.
    def validate_config!
      return if config.available?(:ticket)

      log(:warn, "WhatsApp no disponible para tickets (origen=#{config.source})")
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

    def phone_number_id = config.phone_number_id
  end
end
