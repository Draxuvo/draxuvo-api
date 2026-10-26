# Acceso a la demo que genera el equipo comercial (spec 039). El token en claro se entrega una sola vez al crearla;
# en la base solo queda su huella SHA-256.
class DemoInvite < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :demo_sessions, dependent: :nullify

  validates :plan, inclusion: { in: ->(_) { Plan.keys.map(&:to_s) } }
  validates :scenario, inclusion: { in: ->(_) { Demo::Scenarios.keys } }
  validates :label, length: { in: 2..120 }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :scenario_belongs_to_plan
  validate :expires_in_the_future, on: :create

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_by_token(token)
    return nil if token.blank?

    find_by(token_digest: digest(token))
  end

  # Crea la invitación y devuelve [invitación, token en claro].
  def self.issue!(plan:, scenario:, label:, created_by: nil, expires_at: nil)
    token = SecureRandom.urlsafe_base64(32)
    invite = create!(plan: plan.to_s, scenario: scenario.to_s, label: label.to_s.strip, created_by: created_by,
                     token_digest: digest(token), expires_at: expires_at || Demo::Config.invite_days.days.from_now)
    [ invite, token ]
  end

  # active, expired o revoked (la revocación manda sobre el vencimiento).
  def status
    return "revoked" if revoked_at
    return "expired" if expires_at <= Time.current

    "active"
  end

  def active? = status == "active"

  def revoke!
    update!(revoked_at: Time.current) unless revoked_at
    self
  end

  private

  def scenario_belongs_to_plan
    return if plan.blank? || scenario.blank?

    errors.add(:scenario, :invalid) unless Demo::Scenarios.valid?(plan, scenario)
  end

  def expires_in_the_future
    errors.add(:expires_at, :invalid) if expires_at.present? && expires_at <= Time.current
  end
end
