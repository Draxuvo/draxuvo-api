# Spec 036: quién registró cada marca y si la hora fue capturada (distinta de la actual).
class AddCaptureToAttendances < ActiveRecord::Migration[8.0]
  def change
    add_reference :attendances, :checkin_by, foreign_key: { to_table: :users }, null: true
    add_reference :attendances, :checkout_by, foreign_key: { to_table: :users }, null: true
    add_column :attendances, :checkin_captured, :boolean, null: false, default: false
    add_column :attendances, :checkout_captured, :boolean, null: false, default: false
    add_column :attendances, :checkout_recorded_at, :datetime
  end
end
