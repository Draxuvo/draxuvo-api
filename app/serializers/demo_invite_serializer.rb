# Invitación a la demo para el equipo comercial (spec 039). El token en claro y el enlace solo viajan al crearla
# (`reveal: { token:, url: }`); después no se pueden recuperar, porque en la base solo está la huella.
class DemoInviteSerializer
  # stats: { invite_id => [aperturas, última apertura] }, calculado de una vez para toda la lista.
  def initialize(invite, stats: nil, reveal: nil)
    @invite = invite
    @stats = stats
    @reveal = reveal
  end

  def as_json(*)
    opens, last = stats
    json = {
      id: @invite.id, plan: @invite.plan, scenario: @invite.scenario, label: @invite.label, status: @invite.status,
      expires_at: @invite.expires_at, revoked_at: @invite.revoked_at,
      created_by: @invite.created_by && { id: @invite.created_by.id, name: @invite.created_by.full_name },
      opens_count: opens, last_opened_at: last
    }
    json.merge!(@reveal) if @reveal
    json
  end

  # Aperturas y última apertura de varias invitaciones en dos consultas.
  def self.stats_for(invites)
    DemoSession.where(demo_invite_id: invites.map(&:id)).group(:demo_invite_id)
               .pluck(:demo_invite_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
               .to_h { |id, count, last| [ id, [ count, last ] ] }
  end

  private

  def stats
    @stats&.fetch(@invite.id, nil) || [ 0, nil ]
  end
end
