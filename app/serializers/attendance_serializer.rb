# app/serializers/attendance_serializer.rb
class AttendanceSerializer
  def initialize(attendance)
    @attendance = attendance
  end

  def as_json(*)
    {
      id:              @attendance.id,
      employee_id:     @attendance.employee_id,
      company_id:      @attendance.company_id,
      attendance_type: @attendance.attendance_type,
      checkin_at:      @attendance.checkin_at,
      checkout_at:     @attendance.checkout_at,
      open:            @attendance.open?,
      duration_minutes: @attendance.duration_minutes,
      lat:             @attendance.lat,
      lng:             @attendance.lng,
      created_at:      @attendance.created_at,
      updated_at:      @attendance.updated_at,
      employee: {
        id:       @attendance.employee.id,
        name:     @attendance.employee.name,
        position: @attendance.employee.position
      }
    }
  end
end
