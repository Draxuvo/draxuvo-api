# Teléfono donde una persona tiene sesión y aceptó avisos push (spec 057). Es de la persona, no de una empresa: el aviso
# de cualquier empresa donde sea miembro llega a todos sus dispositivos activos. El token de Expo es único: si otra
# persona inicia sesión en el mismo teléfono, el dispositivo pasa a ella (FR-002). El token completo nunca se serializa.
class PushDevice < ApplicationRecord
  PLATFORMS = %w[android ios].freeze
  LOCALES = %w[es en].freeze
  TOKEN_FORMAT = /\AExp(?:onent|o)PushToken\[[^\[\]\s]{1,200}\]\z/
  STALE_AFTER = 30.days

  belongs_to :user

  validates :token, presence: true, length: { maximum: 255 }, format: { with: TOKEN_FORMAT }, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
  validates :locale, inclusion: { in: LOCALES }
  validates :app_version, length: { maximum: 32 }
  validates :last_seen_at, presence: true

  scope :active, -> { where(disabled_at: nil) }

  def self.valid_token?(token) = TOKEN_FORMAT.match?(token.to_s) && token.to_s.length <= 255

  # Alta o refresco del dispositivo para `user` (upsert por token). Reactiva uno desactivado.
  def self.register!(user:, token:, platform:, locale: nil, app_version: nil)
    device = find_or_initialize_by(token: token.to_s)
    device.assign_attributes(user: user, platform: platform.to_s, locale: LOCALES.include?(locale.to_s) ? locale.to_s : "es",
                             app_version: app_version.presence&.to_s&.first(32), last_seen_at: Time.current,
                             disabled_at: nil, disabled_reason: nil)
    device.save!
    device
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def disable!(reason)
    update_columns(disabled_at: Time.current, disabled_reason: reason, updated_at: Time.current)
  end

  def token_hint = token.to_s.delete_suffix("]").last(6)

  def as_json(*)
    { id: id, platform: platform, locale: locale, token_hint: token_hint, last_seen_at: last_seen_at }
  end

  def serializable_hash(options = nil)
    super((options || {}).merge(except: [ :token ]))
  end
end
