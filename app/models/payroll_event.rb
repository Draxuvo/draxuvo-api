# Bitácora de una corrida (spec 037): solo se inserta, nunca se edita.
class PayrollEvent < ApplicationRecord
  belongs_to :company
  belongs_to :payroll_run
  belongs_to :user

  validates :action, presence: true

  def readonly? = !new_record?
end
