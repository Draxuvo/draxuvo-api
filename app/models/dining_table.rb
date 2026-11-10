# Mesa del local. Está ocupada mientras tiene una cuenta abierta; ese estado se deduce, no se guarda.
class DiningTable < ApplicationRecord
  # Spec 059: 16 bytes aleatorios en base64 URL-safe (22 caracteres, 128 bits): no se adivina ni se deduce de nada.
  MENU_TOKEN_BYTES = 16
  MENU_TOKEN_ATTEMPTS = 3

  belongs_to :company
  has_many :checks, dependent: :restrict_with_error
  has_one :open_check, -> { where(status: :open) }, class_name: "Check", inverse_of: :dining_table

  validates :name, presence: true, uniqueness: { scope: :company_id }
  # Spec 054 (H-47): solo se exige al crear o cambiar el nombre; una mesa vieja con un nombre largo se sigue editando.
  validates :name, length: { maximum: 100 }, if: :will_save_change_to_name?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  # Búsqueda exacta del enlace público (spec 059); un token en blanco no encuentra nada.
  scope :with_menu_token, ->(token) { token.to_s.strip.empty? ? none : where(menu_token: token.to_s) }

  def occupied? = checks.status_open.exists?

  # El enlace se crea la primera vez que un jefe lo consulta o imprime la tarjeta (spec 059, FR-002).
  def ensure_menu_token!
    menu_token.presence || regenerate_menu_token!
  end

  # Token nuevo: el anterior deja de resolver al instante (FR-003).
  def regenerate_menu_token!
    attempts = 0
    begin
      update_columns(menu_token: SecureRandom.urlsafe_base64(MENU_TOKEN_BYTES), menu_token_generated_at: Time.current)
      menu_token
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < MENU_TOKEN_ATTEMPTS
      raise
    end
  end

  # Lo que codifica el QR: la ruta corta del sitio público (`web`), que redirige al idioma del teléfono.
  def menu_url
    return nil if menu_token.blank?

    "#{self.class.public_site_url}/m/#{menu_token}"
  end

  # En producción, sin la variable, el sitio real: un QR impreso con `localhost` no serviría nunca.
  def self.public_site_url
    default = Rails.env.production? ? "https://draxuvo.com" : "http://localhost:4300"
    ENV.fetch("PUBLIC_SITE_URL", default).chomp("/")
  end
end
