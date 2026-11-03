# app/models/user.rb
class User < ApplicationRecord
  include JwtHelper
  has_many :user_companies, dependent: :destroy
  has_many :companies, through: :user_companies
  has_secure_password
  has_many :created_work_orders, class_name: "WorkOrder", as: :created_by
  has_one :employee, dependent: :nullify
  has_one_attached :avatar
  normalizes :email, with: ->(e) { e.strip.downcase }
  # users.role solo distingue a super_admin (global). El rol de empresa vive en user_companies.role (R16).
  enum :role, { staff: 0, admin: 2, owner: 3, super_admin: 4 }, default: :staff

  # Apariencia del panel (spec 006). Las mismas claves viven en draxuvo-ui/src/lib/appearance.ts.
  THEMES = %w[anaquel mercado talavera rosa_mexicano grafito].freeze
  COLOR_MODES = %w[light dark system].freeze

  # Scopes para filtros
  scope :by_email, ->(email) { where("email LIKE ?", "%#{email}%") if email.present? }
  scope :by_role, ->(role) { where(role: role) if role.present? }
  scope :sorted, -> { order(created_at: :desc) }
  # Spec 039: los usuarios efímeros de las demos no cuentan como usuarios reales (no aparecen en lo interno).
  scope :real, -> { where.not(id: UserCompany.joins(:company).where(companies: { demo: true }).select(:user_id)) }
  scope :excluding_system_emails, -> { where.not(email: [ "draxuvo@mailinator.com" ]) }
  # Administrador global de usuarios (spec 036): quienes dirigen una empresa (administrador o dueño en
  # alguna) y quienes aún no tienen empresa. El personal de piso (solo staff) se ve en Personal de su empresa.
  # Ya no se filtra por ficha de empleado: desde la spec 036 toda membresía crea la suya.
  scope :managing, -> {
    where(<<~SQL.squish, managerial: UserCompany.roles.values_at("admin", "owner"))
      NOT EXISTS (SELECT 1 FROM user_companies uc WHERE uc.user_id = users.id)
      OR EXISTS (SELECT 1 FROM user_companies uc WHERE uc.user_id = users.id AND uc.role IN (:managerial))
    SQL
  }
  scope :by_text, ->(text) {
          return unless text

          where_query = <<-SQL
      users.first_name ILIKE :text OR
      users.email ILIKE :text
    SQL

          where(where_query, text: "%#{text}%")
        }
  scope :search, ->(q) { by_text(q) }

  # Validaciones
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :second_last_name, length: { maximum: 50 }, allow_blank: true
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, presence: true
  validates :theme, inclusion: { in: THEMES }
  validates :color_mode, inclusion: { in: COLOR_MODES }
  validates :password, presence: true, if: :password_required?
  validate :password_strength, if: -> { password.present? && password_required? }

  COMMON_PASSWORDS = Set.new(
    File.readlines(Rails.root.join("config/common_passwords.txt"), chomp: true).map { |l| l.strip.downcase }.reject(&:empty?)
  ).freeze

  # Spec 052 (H-38): al menos 8 caracteres, no solo números y fuera de las contraseñas más comunes.
  # Devuelve la clave del problema o nil.
  def self.password_problem(value)
    value = value.to_s
    return :too_short if value.length < 8
    return :only_digits if value.match?(/\A\d+\z/)
    return :common if COMMON_PASSWORDS.include?(value.downcase)

    nil
  end

  def full_name
    [ first_name, middle_name, last_name, second_last_name ].compact.join(" ")
  end

  def locked?
    !active?
  end

  def membership_for(company)
    return nil unless company

    user_companies.find_by(company_id: company.id)
  end

  # Rol con el que actúa en `company`: super_admin es global; si no, el rol de su membresía (o nil).
  def role_in(company)
    return "super_admin" if super_admin?

    membership_for(company)&.role
  end

  # Membresías en orden de alta; la primera define el rol "por compatibilidad" de las respuestas.
  def ordered_memberships
    user_companies.includes(:company).order(:id)
  end

  def compat_role
    return "super_admin" if super_admin?

    ordered_memberships.first&.role || role
  end

  # Method to update password with confirmation
  def update_password(current_password, new_password, new_password_confirmation)
    errors.add(:current_password, "es incorrecta") unless authenticate(current_password)
    errors.add(:new_password, "no puede estar vacía") if new_password.blank?
    add_new_password_problem(new_password)
    errors.add(:new_password_confirmation, "no coincide con la nueva contraseña") if new_password != new_password_confirmation

    return false unless errors.empty?

    update(password: new_password)
  end

  # Method to reset password with token validation
  def reset_password_with_token(token, new_password, new_password_confirmation)
    errors.add(:new_password, "no puede estar vacía") if new_password.blank?
    add_new_password_problem(new_password)
    errors.add(:new_password_confirmation, "no coincide con la nueva contraseña") if new_password != new_password_confirmation

    return false unless errors.empty?

    update(password: new_password)
  end

  private

  def password_strength
    problem = self.class.password_problem(password)
    errors.add(:password, I18n.t("auth.weak_password.#{problem}")) if problem
  end

  def add_new_password_problem(value)
    problem = self.class.password_problem(value) if value.present?
    errors.add(:new_password, I18n.t("auth.weak_password.#{problem}")) if problem
  end

  def password_required?
    # Require password for new records or when password is being changed
    new_record? || !password.nil?
  end
end
