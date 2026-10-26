# Apertura de una demo para el equipo comercial (spec 039). Nunca lleva IP ni agente de navegador: no se guardan.
class DemoSessionSerializer
  def initialize(session)
    @session = session
  end

  def as_json(*)
    {
      id: @session.id, plan: @session.plan, scenario: @session.scenario, locale: @session.locale,
      created_at: @session.created_at, expires_at: @session.expires_at, ended_at: @session.ended_at,
      ended_reason: @session.ended_reason, purged_at: @session.purged_at,
      invite: @session.demo_invite && { id: @session.demo_invite.id, label: @session.demo_invite.label },
      contact: @session.contact? ? { name: @session.contact_name, email: @session.contact_email, phone: @session.contact_phone } : nil
    }
  end
end
