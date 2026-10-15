# app/models/work_order_step.rb
# Algo por hacer dentro de una orden. No tiene precio.
class WorkOrderStep < ApplicationRecord
  belongs_to :work_order
  belongs_to :done_by, polymorphic: true, optional: true

  validates :description, presence: true, length: { maximum: 255 }
  validates :position, numericality: { greater_than_or_equal_to: 0 }

  def done?
    done_at.present?
  end

  def mark_done!(by)
    update!(done_at: Time.current, done_by: by)
  end

  def mark_undone!
    update!(done_at: nil, done_by: nil)
  end
end
