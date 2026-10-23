# Importación de productos desde Excel que corre en segundo plano (spec 034).
class ProductImport < ApplicationRecord
  STALE_AFTER = 10.minutes
  MAX_ERRORS = 500
  MAX_BYTES = 5.megabytes
  MAX_ROWS = 10_000

  belongs_to :company
  belongs_to :user

  enum :status, { queued: 0, processing: 1, done: 2, failed: 3 }, default: :queued

  scope :active, -> { where(status: %i[queued processing]) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Una importación `processing` sin cambios en 10 minutos se da por caída (reinicio del servidor).
  def self.fail_stale!
    where(status: :processing).where(updated_at: ...STALE_AFTER.ago).find_each do |import|
      import.update!(status: :failed, finished_at: Time.current, file_data: nil,
                     errors_list: import.errors_list + [ { "row" => nil, "error" => I18n.t("products.import.interrupted") } ])
    end
  end
end
