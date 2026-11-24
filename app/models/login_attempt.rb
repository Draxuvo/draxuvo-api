# Bitácora de inicios de sesión (spec 073): un renglón por intento en POST /auth/login, con su resultado. Solo inserción y
# solo la lee el super admin. Nunca guarda la contraseña ni el token; LoginAttempts::PurgeJob borra lo que pasa de 90 días.
class LoginAttempt < ApplicationRecord
  RESULTS = %w[success wrong_password unknown_email inactive rate_limited invalid].freeze
  FAILURES = (RESULTS - %w[success]).freeze
  CHANNELS = %w[panel app unknown].freeze
  # Resultados en los que el correo tenía cuenta: sin `user_id`, la persona se borró después.
  WITH_ACCOUNT = %w[success wrong_password inactive].freeze
  ZONE = "America/Mexico_City".freeze
  MAX_SINCE_MINUTES = 1440

  belongs_to :user, optional: true

  validates :result, inclusion: { in: RESULTS }
  validates :channel, inclusion: { in: CHANNELS }
  validates :email, presence: true, length: { maximum: 254 }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :failures, -> { where(result: FAILURES) }
  scope :since, ->(time) { where(created_at: time..) }

  def readonly?
    persisted? || super
  end

  # Filtros de GET /login_attempts (contracts/api.md). Los valores ya vienen validados por el controlador; los que no se
  # reconocen se ignoran.
  def self.filtered(params)
    params = params.to_h.with_indifferent_access
    scope = all
    scope = filter_results(scope, Array(params[:result]))
    scope = filter_text(scope, params[:q])
    scope = scope.where(user_id: UserCompany.where(company_id: params[:company_id]).select(:user_id)) if params[:company_id].present?
    scope = scope.where(ip: params[:ip]) if params[:ip].present?
    scope = scope.where(channel: params[:channel]) if CHANNELS.include?(params[:channel])
    scope = filter_since(scope, params[:since])
    filter_dates(scope, params[:from], params[:to])
  end

  def self.filter_results(scope, values)
    results = values.flat_map { |value| value == "failures" ? FAILURES : value }.select { |value| RESULTS.include?(value) }
    results.empty? ? scope : scope.where(result: results.uniq)
  end

  def self.filter_text(scope, text)
    text = text.to_s.strip
    return scope if text.empty?

    pattern = "%#{sanitize_sql_like(text)}%"
    names = User.where("CONCAT_WS(' ', first_name, middle_name, last_name, second_last_name) ILIKE :p", p: pattern).select(:id)
    scope.where("login_attempts.email ILIKE :p", p: pattern).or(scope.where(user_id: names))
  end

  def self.filter_since(scope, minutes)
    minutes = minutes.to_i
    return scope unless minutes.between?(1, MAX_SINCE_MINUTES)

    scope.since(minutes.minutes.ago)
  end

  def self.filter_dates(scope, from, to)
    zone = Time.find_zone!(ZONE)
    scope = scope.where(created_at: zone.parse(from.to_s).beginning_of_day..) if from.present?
    scope = scope.where(created_at: ..zone.parse(to.to_s).end_of_day) if to.present?
    scope
  end

  private_class_method :filter_results, :filter_text, :filter_since, :filter_dates

  # La persona se borró: el intento era de una cuenta existente y ya no tiene enlace.
  def deleted_user?
    user_id.nil? && WITH_ACCOUNT.include?(result)
  end
end
