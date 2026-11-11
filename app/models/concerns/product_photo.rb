# Foto del producto para el menú QR (spec 061). Una por producto, con su estilo en el menú: tarjeta grande o miniatura.
#
# El original (hasta 10 MB) se guarda tal cual y nunca sale al público. El comensal recibe dos versiones WebP sin
# metadatos (sin la ubicación GPS del EXIF), recortadas al centro: `card` (960×720) y `thumb` (240×240). Ambas se
# generan en segundo plano al subir la foto (`preprocessed`), así que cambiar de estilo no pide volver a subirla.
# Contrato: specs/061-imagenes-menu-qr/contracts/api.md; decisiones en research.md (R1–R3).
module ProductPhoto
  extend ActiveSupport::Concern

  PHOTO_STYLES = %w[card thumbnail].freeze
  # Tipo que identifica Active Storage por el contenido del archivo → extensión del nombre normalizado.
  PHOTO_TYPES = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze
  PHOTO_MAX_SIZE = 10.megabytes
  # Las URLs firmadas duran al menos lo que el comensal tiene el menú abierto (FR-018).
  PHOTO_URL_TTL = 1.hour
  PHOTO_SAVER = { quality: 72, strip: true }.freeze

  included do
    belongs_to :photo_updated_by, class_name: "User", optional: true

    has_one_attached :photo do |attachable|
      attachable.variant :card, resize_to_fill: [ 960, 720 ], format: :webp, saver: PHOTO_SAVER, preprocessed: true
      attachable.variant :thumb, resize_to_fill: [ 240, 240 ], format: :webp, saver: PHOTO_SAVER, preprocessed: true
    end

    validates :photo_style, inclusion: { in: PHOTO_STYLES, message: ->(*) { I18n.t("products.photo.invalid_style") } }
    validate :photo_acceptable, if: -> { attachment_changes["photo"].present? && photo.attached? }

    # Precarga lo que necesitan `photo_ready?` y las URLs, para no consultar por producto (menú público).
    scope :with_photo_variants, -> { includes(photo_attachment: { blob: { variant_records: { image_attachment: :blob } } }) }
  end

  # Sube o reemplaza la foto. El nombre del archivo del cliente no se guarda: queda `foto.<ext>`. La foto anterior se
  # purga sola (has_one_attached). Lanza ActiveRecord::RecordInvalid si el tipo, el tamaño o el estilo no sirven, sin
  # cambiar nada.
  def attach_photo!(file, style: nil, user: nil)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    declared = file.respond_to?(:content_type) ? file.content_type : nil
    self.photo = { io: io, filename: "foto", content_type: declared, identify: true }
    blob = attachment_changes["photo"].blob
    blob.filename = "foto.#{PHOTO_TYPES.fetch(blob.content_type.to_s, 'bin')}"
    self.photo_style = style.presence || "card"
    self.photo_updated_by = user
    save!
  end

  def update_photo_style!(style, user: nil)
    update!(photo_style: style.to_s, photo_updated_by: user)
  end

  # Quita la foto y deja el estilo por omisión (spec 061, casos especiales).
  def remove_photo!
    transaction do
      photo.purge_later
      update!(photo_style: "card", photo_updated_by: nil)
    end
  end

  # Lista para el comensal: las dos versiones ya existen (FR-011). Mientras no, el menú muestra el icono.
  def photo_ready?
    photo.attached? && %i[card thumb].all? { |name| photo_variant_processed?(name) }
  end

  # El campo `photo` del contrato. Público: solo estilo y URLs, y nada si aún no está lista. Panel: además `ready` y la
  # fecha, para que el formulario sepa cuándo dejar de esperar.
  def photo_payload(public:)
    return nil unless photo.attached?

    ready = photo_ready?
    if public
      return nil unless ready

      payload = { style: photo_style, url: photo_variant_url(:card) }
      payload[:thumbnail_url] = photo_variant_url(:thumb) if photo_style == "thumbnail"
      payload
    else
      { style: photo_style, ready: ready,
        url: ready ? photo_variant_url(:card) : nil,
        thumbnail_url: ready ? photo_variant_url(:thumb) : nil,
        updated_at: photo.attachment.created_at }
    end
  end

  private

  # `VariantWithRecord#processed?` es privado; `image` es público y usa los registros precargados (with_photo_variants).
  def photo_variant_processed?(name)
    photo.variant(name).image&.attached? || false
  end

  def photo_variant_url(name)
    photo.variant(name).url(expires_in: PHOTO_URL_TTL)
  end

  def photo_acceptable
    blob = photo.blob
    errors.add(:photo, :invalid_type, message: I18n.t("products.photo.invalid_type")) unless PHOTO_TYPES.key?(blob.content_type.to_s)
    errors.add(:photo, :too_large, message: I18n.t("products.photo.too_large")) if blob.byte_size.to_i > PHOTO_MAX_SIZE
  end
end
