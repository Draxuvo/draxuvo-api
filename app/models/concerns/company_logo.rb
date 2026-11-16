# Logo propio de la empresa (spec 063). Uno por empresa; cada sucursal tiene el suyo y no hereda el de la principal.
#
# El original (JPG, PNG o WebP de hasta 5 MB; sin SVG) se guarda tal cual y nunca se muestra. Se preparan en segundo plano
# dos versiones sin metadatos y sin recortar (un logo ancho se ve completo): `display` (WebP, máx. 512 px) para el panel,
# la app y el menú QR, y `print` (PNG, máx. 600 px) para el PDF del ticket, porque Prawn solo lee PNG y JPG.
# Contrato: specs/063-logo-empresa/contracts/api.md; decisiones en research.md (R1–R5).
module CompanyLogo
  extend ActiveSupport::Concern

  # Tipo que identifica Active Storage por el contenido del archivo → extensión del nombre normalizado.
  LOGO_TYPES = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze
  LOGO_MAX_SIZE = 5.megabytes
  # Solo el menú público usa URLs firmadas (como las fotos de la spec 061); el panel y la app usan la redirección.
  LOGO_URL_TTL = 1.hour

  included do
    belongs_to :logo_updated_by, class_name: "User", optional: true

    has_one_attached :logo do |attachable|
      attachable.variant :display, resize_to_limit: [ 512, 512 ], format: :webp, saver: { quality: 85, strip: true }, preprocessed: true
      attachable.variant :print, resize_to_limit: [ 600, 600 ], format: :png, saver: { strip: true }, preprocessed: true
    end

    validate :logo_acceptable, if: -> { attachment_changes["logo"].present? && logo.attached? }
  end

  # Sube o reemplaza el logo. El nombre del archivo del cliente no se guarda: queda `logo.<ext>`. El anterior se purga solo
  # (has_one_attached). Lanza ActiveRecord::RecordInvalid si el tipo o el tamaño no sirven, sin cambiar nada.
  def attach_logo!(file, user: nil)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    declared = file.respond_to?(:content_type) ? file.content_type : nil
    self.logo = { io: io, filename: "logo", content_type: declared, identify: true }
    blob = attachment_changes["logo"].blob
    blob.filename = "logo.#{LOGO_TYPES.fetch(blob.content_type.to_s, 'bin')}"
    self.logo_updated_by = user
    self.logo_updated_at = Time.current
    save!
  end

  # Quita el logo y registra quién y cuándo (FR-013).
  def remove_logo!(user: nil)
    transaction do
      logo.purge_later
      update!(logo_updated_by: user, logo_updated_at: Time.current)
    end
  end

  def logo_ready?
    logo.attached? && (logo.variant(:display).image&.attached? || false)
  end

  # Para la sesión del panel y de la app, que se guarda por días: la redirección de Active Storage no caduca y cambia
  # cuando se reemplaza el logo (otro blob), así que la caché del cliente se invalida sola (research R3).
  def logo_redirect_url
    return nil unless logo.attached?

    Rails.application.routes.url_helpers.rails_representation_url(logo.variant(:display))
  end

  # Para el menú público: URL firmada que caduca, y nada mientras la versión no esté lista (research R4).
  def logo_public_url
    return nil unless logo_ready?

    logo.variant(:display).url(expires_in: LOGO_URL_TTL)
  end

  # El objeto `logo` del contrato (respuesta de PUT /company/logo y empresas del super admin).
  def logo_payload
    return nil unless logo.attached?

    updater = logo_updated_by
    { url: logo_redirect_url, updated_at: logo_updated_at,
      updated_by: updater && { id: updater.id, name: updater.full_name } }
  end

  # La versión para imprimir (PNG), o nil si no hay logo o no se pudo preparar. El PDF del ticket nunca falla por el logo.
  def logo_print_io
    return nil unless logo.attached?

    StringIO.new(logo.variant(:print).processed.download)
  rescue StandardError => e
    Rails.logger.warn("[CompanyLogo] company=#{id} print logo unavailable: #{e.class}: #{e.message}")
    nil
  end

  private

  def logo_acceptable
    blob = logo.blob
    errors.add(:logo, :invalid_type, message: I18n.t("companies.logo.invalid_type")) unless LOGO_TYPES.key?(blob.content_type.to_s)
    errors.add(:logo, :too_large, message: I18n.t("companies.logo.too_large")) if blob.byte_size.to_i > LOGO_MAX_SIZE
  end
end
