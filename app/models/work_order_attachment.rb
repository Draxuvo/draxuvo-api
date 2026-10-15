# app/models/work_order_attachment.rb
class WorkOrderAttachment < ApplicationRecord
  MAX_SIZE = 10.megabytes
  MAX_PER_ORDER = 10
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze

  belongs_to :work_order
  belongs_to :uploaded_by, polymorphic: true
  has_one_attached :file

  validates :file, presence: true
  validate :file_is_image, if: -> { file.attached? }
  validate :file_within_size, if: -> { file.attached? }
  validate :order_under_limit, on: :create

  private

  def file_is_image
    return if ALLOWED_TYPES.include?(file.blob.content_type.to_s)

    errors.add(:file, I18n.t("work_order.photo.invalid_type"))
  end

  def file_within_size
    return if file.blob.byte_size <= MAX_SIZE

    errors.add(:file, I18n.t("work_order.photo.too_large"))
  end

  def order_under_limit
    return unless work_order
    return if work_order.work_order_attachments.where.not(id: nil).count < MAX_PER_ORDER

    errors.add(:base, I18n.t("work_order.photo.limit_reached"))
  end
end
