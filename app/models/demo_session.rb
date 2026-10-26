# Cada apertura de una demo (spec 039). Sobrevive a la purga de la empresa: company_id y user_id se anulan y quedan el
# plan, el escenario, el contacto y las fechas para el seguimiento comercial. No guarda IP ni agente de navegador.
class DemoSession < ApplicationRecord
  LOCALES = %w[es en].freeze
  ENDED_REASONS = %w[left signup expired].freeze

  belongs_to :company, optional: true
  belongs_to :user, optional: true
  belongs_to :demo_invite, optional: true

  validates :plan, inclusion: { in: ->(_) { Plan.keys.map(&:to_s) } }
  validates :scenario, inclusion: { in: ->(_) { Demo::Scenarios.keys } }
  validates :locale, inclusion: { in: LOCALES }
  validates :expires_at, presence: true
  validates :ended_reason, inclusion: { in: ENDED_REASONS }, allow_nil: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :contact_phone, format: { with: /\A\d{10}\z/ }, allow_blank: true
  validates :contact_name, length: { maximum: 120 }

  # Ni purgada, ni terminada, ni vencida: cuenta para el tope de demos activas.
  scope :active, -> { where(purged_at: nil, ended_at: nil).where("expires_at > ?", Time.current) }
  # Lo que le toca a la purga: vencida o terminada y todavía sin purgar.
  scope :purgeable, -> { where(purged_at: nil).where("expires_at <= :now OR ended_at IS NOT NULL", now: Time.current) }

  def expired? = expires_at <= Time.current

  def ended? = ended_at.present?

  # Una demo deja de servir al vencer o al terminarla el visitante.
  def usable? = purged_at.nil? && !ended? && !expired?

  def contact? = [ contact_name, contact_email, contact_phone ].any?(&:present?)
end
