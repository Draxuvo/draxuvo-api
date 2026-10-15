# app/models/work_order_event.rb
# Historia de la orden: solo se insertan, no se editan ni se borran.
class WorkOrderEvent < ApplicationRecord
  belongs_to :work_order
  belongs_to :actor, polymorphic: true

  enum :kind, {
    created: 0, started: 1, finished: 2, reopened: 3, charged: 4,
    voided: 5, cancelled: 6, reassigned: 7, note: 8, photo: 9
  }, validate: true

  validates :kind, presence: true
  validates :data, exclusion: { in: [ nil ] }
  validate :note_text, if: :note?

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy :forbid_destroy

  private

  def note_text
    text = data.is_a?(Hash) ? data["text"].to_s : ""
    errors.add(:data, :blank) if text.strip.empty?
    errors.add(:data, :too_long, count: 2000) if text.length > 2000
  end

  # Se permite borrar solo en cascada al destruir la orden.
  def forbid_destroy
    throw :abort unless destroyed_by_association
  end
end
