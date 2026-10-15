# app/models/attendance.rb
class Attendance < ApplicationRecord
  belongs_to :employee
  belongs_to :company

  enum :attendance_type, { normal: 0, late: 1, absent: 2 }, default: :normal

  validates :checkin_at, presence: true

  scope :search, ->(q) {
    joins(:employee).where("employees.name ILIKE :q", q: "%#{q}%") if q.present?
  }
end
