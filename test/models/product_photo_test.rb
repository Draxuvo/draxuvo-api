require "test_helper"

# Spec 061: foto del producto para el menú QR (concern ProductPhoto).
class ProductPhotoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FILES = Rails.root.join("test/fixtures/files")
  PNG_HEADER = "\x89PNG\r\n\x1A\n".b

  def upload(name, type)
    Rack::Test::UploadedFile.new(FILES.join(name), type, original_filename: "Mi platillo favorito #{name}")
  end

  def product = products(:resto_tacos)

  test "acepta JPG, PNG y WebP y normaliza el nombre del archivo" do
    { "foto.jpg" => [ "image/jpeg", "jpg" ], "foto.png" => [ "image/png", "png" ], "foto.webp" => [ "image/webp", "webp" ] }.each do |name, (type, ext)|
      product.attach_photo!(upload(name, type), user: users(:resto_owner))
      assert product.reload.photo.attached?, "#{name} debería guardarse"
      assert_equal "foto.#{ext}", product.photo.filename.to_s
    end
  end

  test "guarda el estilo elegido y quién subió la foto" do
    product.attach_photo!(upload("foto.png", "image/png"), style: "thumbnail", user: users(:resto_owner))
    assert_equal "thumbnail", product.reload.photo_style
    assert_equal users(:resto_owner), product.photo_updated_by
  end

  test "sin estilo queda en tarjeta grande" do
    product.update!(photo_style: "thumbnail")
    product.attach_photo!(upload("foto.png", "image/png"))
    assert_equal "card", product.reload.photo_style
  end

  test "rechaza HEIC aunque el cliente diga que es JPG, sin cambiar la foto anterior" do
    product.attach_photo!(upload("foto.png", "image/png"))
    blob = product.reload.photo.blob

    error = assert_raises(ActiveRecord::RecordInvalid) { product.attach_photo!(upload("foto.heic", "image/jpeg")) }
    assert_includes error.record.errors[:photo], I18n.t("products.photo.invalid_type")
    assert_equal blob, product.reload.photo.blob
  end

  test "rechaza un archivo que no es imagen" do
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 contenido"), "image/png", original_filename: "menu.png")
    error = assert_raises(ActiveRecord::RecordInvalid) { product.attach_photo!(pdf) }
    assert error.record.errors.details[:photo].any? { |detail| detail[:error] == :invalid_type }
  end

  test "rechaza una foto de más de 10 MB" do
    big = Rack::Test::UploadedFile.new(StringIO.new(PNG_HEADER + ("\x00".b * ProductPhoto::PHOTO_MAX_SIZE)), "image/png", original_filename: "grande.png")
    error = assert_raises(ActiveRecord::RecordInvalid) { product.attach_photo!(big) }
    assert_includes error.record.errors[:photo], I18n.t("products.photo.too_large")
  end

  test "un estilo fuera de la lista es inválido" do
    product.photo_style = "poster"
    assert_not product.valid?
    assert_includes product.errors[:photo_style], I18n.t("products.photo.invalid_style")
  end

  test "reemplazar la foto purga la anterior" do
    product.attach_photo!(upload("foto.png", "image/png"))
    old = product.reload.photo.blob

    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ old ]) do
      product.attach_photo!(upload("foto.jpg", "image/jpeg"))
    end
    assert_not_equal old, product.reload.photo.blob
  end

  test "quitar la foto la purga y deja el estilo en tarjeta" do
    product.attach_photo!(upload("foto.png", "image/png"), style: "thumbnail", user: users(:resto_owner))
    blob = product.reload.photo.blob

    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ blob ]) { product.remove_photo! }
    product.reload
    assert_not product.photo.attached?
    assert_equal "card", product.photo_style
    assert_nil product.photo_updated_by
  end

  test "la foto se prepara en segundo plano: lista solo con sus dos versiones" do
    product.attach_photo!(upload("foto.jpg", "image/jpeg"))
    product.reload
    assert_not product.photo_ready?
    assert_nil product.photo_payload(public: true)
    assert_equal false, product.photo_payload(public: false)[:ready]

    perform_enqueued_jobs
    assert product.reload.photo_ready?
  end

  test "las versiones públicas son WebP del tamaño de la tarjeta y la miniatura, sin EXIF" do
    product.attach_photo!(upload("foto.jpg", "image/jpeg"))
    perform_enqueued_jobs
    product.reload

    { card: [ 960, 720 ], thumb: [ 240, 240 ] }.each do |name, (width, height)|
      image = product.photo.variant(name).image
      assert_equal "image/webp", image.content_type
      image.blob.open do |file|
        vips = Vips::Image.new_from_file(file.path)
        assert_equal [ width, height ], [ vips.width, vips.height ], "#{name}: tamaño"
        assert_not_includes vips.get_fields, "exif-data", "#{name}: no debe llevar EXIF"
      end
    end
  end

  test "el campo público trae solo estilo y URLs, sin ids ni el nombre original" do
    product.attach_photo!(upload("foto.png", "image/png"), style: "thumbnail")
    perform_enqueued_jobs
    ActiveStorage::Current.url_options = { host: "http://example.test" }
    payload = product.reload.photo_payload(public: true)

    assert_equal %i[style url thumbnail_url].sort, payload.keys.sort
    assert_equal "thumbnail", payload[:style]
    [ payload[:url], payload[:thumbnail_url] ].each do |url|
      assert_no_match(/Mi%20platillo|Mi\+platillo|favorito/, url)
      assert_no_match(%r{/products?/#{product.id}\b}, url)
    end
  ensure
    ActiveStorage::Current.reset
  end
end
