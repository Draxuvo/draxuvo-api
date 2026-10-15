require "test_helper"

class WorkOrderAttachmentTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\x00".b * 32)

  def build_attachment(order: work_orders(:pro_open), content_type: "image/png", bytes: PNG, attach: true)
    attachment = WorkOrderAttachment.new(work_order: order, uploaded_by: users(:pro_staff))
    if attach
      attachment.file.attach(io: StringIO.new(bytes), filename: "foto.png", content_type: content_type)
    end
    attachment
  end

  test "an image is valid" do
    assert build_attachment.valid?
  end

  test "a file is required" do
    attachment = build_attachment(attach: false)
    assert_not attachment.valid?
    assert attachment.errors[:file].any?
  end

  test "allowed image types are accepted" do
    WorkOrderAttachment::ALLOWED_TYPES.each do |type|
      attachment = build_attachment(content_type: type, bytes: "contenido de prueba")
      assert attachment.valid?, "#{type} debería ser válido"
    end
  end

  test "a non image is rejected" do
    attachment = build_attachment(content_type: "application/pdf", bytes: "%PDF-1.4 contenido")
    assert_not attachment.valid?
    assert_includes attachment.errors[:file], I18n.t("work_order.photo.invalid_type")
  end

  test "a file over 10 MB is rejected" do
    attachment = build_attachment(bytes: "a".b * (WorkOrderAttachment::MAX_SIZE + 1))
    assert_not attachment.valid?
    assert_includes attachment.errors[:file], I18n.t("work_order.photo.too_large")
  end

  test "exactly 10 MB is accepted" do
    assert build_attachment(bytes: "a".b * WorkOrderAttachment::MAX_SIZE).valid?
  end

  test "an order accepts at most 10 photos" do
    order = work_orders(:pro_open)
    10.times { build_attachment(order: order).save! }
    eleventh = build_attachment(order: order)
    assert_not eleventh.valid?
    assert_includes eleventh.errors[:base], I18n.t("work_order.photo.limit_reached")
    assert build_attachment(order: work_orders(:pro_started)).valid?
  end

  test "attachments are removed with their order" do
    order = work_orders(:pro_open)
    build_attachment(order: order).save!
    assert_difference -> { WorkOrderAttachment.count }, -1 do
      order.destroy!
    end
  end
end
