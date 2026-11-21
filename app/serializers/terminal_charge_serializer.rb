# Solicitud de cobro en una terminal integrada (spec 069, contracts/api.md, «Forma de una solicitud»).
class TerminalChargeSerializer
  def initialize(charge, boss: false, user: nil)
    @charge = charge
    @boss = boss
    @user = user
  end

  def as_json(*)
    owner = TerminalCharges::Owner.for_charge(@charge)
    {
      id: @charge.id, status: @charge.status, status_detail: @charge.status_detail, amount: format("%.2f", @charge.amount),
      terminal: PaymentTerminalSerializer.ref(@charge.payment_terminal),
      owner: { type: owner.type, id: owner.record.id, label: owner.label },
      created_by: @charge.created_by && { id: @charge.created_by.id, name: @charge.created_by.full_name },
      created_at: @charge.created_at, expires_at: @charge.expires_at, resolved_at: @charge.resolved_at,
      provider_reference: @charge.provider_reference, card_last4: @charge.card_last4,
      unapplied_reason: @charge.unapplied_reason,
      result: @charge.applied? ? @charge.params["result"] : nil,
      refund: @charge.terminal_refund&.as_payment_json,
      allowed_actions: allowed_actions
    }
  end

  private

  def allowed_actions
    actions = []
    actions << "cancel" if @charge.pending?
    actions << "abandon" if @charge.open?
    if @boss && @charge.unapplied? && !@charge.terminal_refund&.settled?
      actions << "refund"
      actions << "dismiss"
    end
    actions
  end
end
