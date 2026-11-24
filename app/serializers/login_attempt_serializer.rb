# Un intento de la bitácora con la forma de specs/073-bitacora-accesos-estado/contracts/api.md. Espera la persona con sus
# membresías y empresas precargadas.
class LoginAttemptSerializer
  def initialize(attempt)
    @attempt = attempt
  end

  def as_json(*)
    {
      id: @attempt.id, created_at: @attempt.created_at, result: @attempt.result, email: @attempt.email,
      user: user_json, companies: companies_json, ip: @attempt.ip&.to_s, channel: @attempt.channel,
      device: device, user_agent: @attempt.user_agent,
      client_version: @attempt.client_version, demo: @attempt.demo
    }
  end

  private

  # `nil` si no se reconoce: el panel lo traduce.
  def device
    summary = UserAgentSummary.call(@attempt.user_agent)
    summary == UserAgentSummary::UNKNOWN ? nil : summary
  end

  def user_json
    return { id: @attempt.user.id, name: @attempt.user.full_name, deleted: false } if @attempt.user
    return { id: nil, name: nil, deleted: true } if @attempt.deleted_user?

    nil
  end

  def companies_json
    return [] unless @attempt.user

    @attempt.user.user_companies.map(&:company).sort_by(&:name).map { |company| { id: company.id, name: company.name } }
  end
end
