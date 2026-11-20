# Cuenta de un proveedor de terminal conectada por una empresa (spec 069, data-model.md). Una por proveedor y empresa
# (FR-002); la principal y sus sucursales pueden conectar la misma cuenta del proveedor. Los tokens van cifrados en reposo,
# nunca se serializan ni se registran (FR-003).
class TerminalConnection < ApplicationRecord
  STATUSES = %w[connected error disconnected].freeze
  PROVIDERS = TerminalProviders.providers.freeze

  encrypts :access_token, :refresh_token

  belongs_to :company
  belongs_to :connected_by, class_name: "User", optional: true
  has_many :payment_terminals, dependent: :restrict_with_error
  has_many :terminal_charges, dependent: :restrict_with_error

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :company_id }
  validates :status, inclusion: { in: STATUSES }

  scope :connected, -> { where(status: "connected") }

  def connected? = status == "connected"
  def error? = status == "error"
  def disconnected? = status == "disconnected"

  # El token en claro, o nil si no hay o ya no se puede descifrar (por ejemplo, tras rotar SECRET_KEY_BASE).
  def token
    access_token
  rescue ActiveRecord::Encryption::Errors::Decryption
    nil
  end

  def renewal_token
    refresh_token
  rescue ActiveRecord::Encryption::Errors::Decryption
    nil
  end

  # Guarda las credenciales de una autorización o una renovación y deja la conexión al corriente.
  def store_credentials!(credentials, user: nil)
    attrs = { access_token: credentials.access_token, token_expires_at: credentials.expires_at,
              live_mode: credentials.live_mode != false, status: "connected", error_code: nil, error_message: nil,
              problem_notified_at: nil, disconnected_at: nil }
    attrs[:refresh_token] = credentials.refresh_token if credentials.refresh_token.present?
    attrs[:account_id] = credentials.account_id.to_s if credentials.account_id.present?
    attrs[:account_label] = credentials.account_label if credentials.account_label.present?
    if user
      attrs[:connected_by] = user
      attrs[:connected_at] = Time.current
    else
      attrs[:last_refreshed_at] = Time.current
    end
    update!(attrs)
  end

  # Borra las credenciales y deja la conexión desconectada; conserva la fila, sus terminales y su historial (FR-004).
  def disconnect!
    update!(access_token: nil, refresh_token: nil, token_expires_at: nil, status: "disconnected",
            disconnected_at: Time.current, error_code: nil, error_message: nil, problem_notified_at: nil)
  end

  def provider_client = TerminalProviders.for(provider)

  # Nunca incluye los tokens (ni cifrados) al serializar.
  def serializable_hash(options = nil)
    options = (options || {}).dup
    options[:except] = Array(options[:except]) + %w[access_token refresh_token]
    super(options)
  end

  def inspect = "#<TerminalConnection id: #{id.inspect}, company_id: #{company_id.inspect}, provider: #{provider.inspect}, status: #{status.inspect}>"
end
