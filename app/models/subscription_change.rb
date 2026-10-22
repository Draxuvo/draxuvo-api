# Un cambio de suscripción (spec 031, FR-016): cambio de plan de prueba por el super admin, suspensión,
# reactivación o cancelación automática. Solo se inserta. `actor` es nulo cuando lo hace el sistema.
class SubscriptionChange < ApplicationRecord
  KINDS = %w[trial_plan_changed suspended reactivated auto_cancelled].freeze

  belongs_to :company
  belongs_to :subscription
  belongs_to :actor, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
end
