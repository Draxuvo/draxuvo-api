# app/models/attendance.rb
class Attendance < ApplicationRecord
  belongs_to :employee
  belongs_to :company
  belongs_to :checkin_by,  class_name: "User", optional: true
  belongs_to :checkout_by, class_name: "User", optional: true

  enum :attendance_type, { normal: 0, late: 1, absent: 2 }, default: :normal

  validates :checkin_at, presence: true

  # Turno en curso: de hoy y sin salida. Una entrada sin salida de un día anterior no está "abierta".
  def open?
    checkout_at.nil? && Time.zone.today.all_day.cover?(checkin_at)
  end

  def duration_minutes
    ((checkout_at - checkin_at) / 60).floor if checkout_at
  end

  scope :search, ->(q) {
    joins(:employee).where("employees.name ILIKE :q", q: "%#{q}%") if q.present?
  }
end
