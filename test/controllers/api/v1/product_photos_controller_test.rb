require "test_helper"

# Spec 061: PUT, PATCH y DELETE /api/v1/products/:id/photo (contracts/api.md).
class Api::V1::ProductPhotosControllerTest < ActionDispatch::IntegrationTest
  FILES = Rails.root.join("test/fixtures/files")
  PNG_HEADER = "\x89PNG\r\n\x1A\n".b

  setup do
    @company = companies(:resto_co)
    @owner = auth_headers(users(:resto_owner), @company)
    @product = products(:resto_sopa)
  end

  def file(name = "foto.jpg", type = "image/jpeg")
    Rack::Test::UploadedFile.new(FILES.join(name), type, original_filename: name)
  end

  def path(product = @product) = "/api/v1/products/#{product.id}/photo"

  def put_photo(params = { file: file }, headers: @owner, product: @product)
    put path(product), params: params, headers: headers
  end

  def error_code = response.parsed_body.dig("error", "details", "code")

  test "the owner uploads a photo: card by default, still being prepared" do
    put_photo
    assert_response :ok
    photo = response.parsed_body["photo"]
    assert_equal "card", photo["style"]
    assert_equal false, photo["ready"]
    assert_nil photo["url"]
    assert @product.reload.photo.attached?
    assert_equal users(:resto_owner), @product.photo_updated_by
  end

  test "the photo is ready after the background job, with both urls" do
    put_photo
    perform_enqueued_jobs
    get "/api/v1/products/#{@product.id}", headers: @owner
    photo = response.parsed_body["photo"]
    assert photo["ready"]
    assert photo["url"].present?
    assert photo["thumbnail_url"].present?
  end

  test "the owner can choose the thumbnail style when uploading" do
    put_photo({ file: file, style: "thumbnail" })
    assert_response :ok
    assert_equal "thumbnail", response.parsed_body.dig("photo", "style")
  end

  test "replacing the photo purges the previous one and keeps the rest of the product" do
    put_photo
    old = @product.reload.photo.blob
    name, price = @product.name, @product.price

    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ old ]) { put_photo({ file: file("foto.png", "image/png") }) }
    @product.reload
    assert_not_equal old, @product.photo.blob
    assert_equal [ name, price ], [ @product.name, @product.price ]
  end

  test "PUT without a file answers 422 photo_missing" do
    put_photo({ style: "card" })
    assert_response :unprocessable_entity
    assert_equal "photo_missing", error_code
  end

  test "a HEIC photo answers 422 photo_invalid_type and keeps the previous photo" do
    put_photo
    old = @product.reload.photo.blob

    put_photo({ file: file("foto.heic", "image/jpeg") })
    assert_response :unprocessable_entity
    assert_equal "photo_invalid_type", error_code
    assert_equal I18n.t("products.photo.invalid_type"), response.parsed_body.dig("error", "message")
    assert_equal old, @product.reload.photo.blob
  end

  test "a photo over 10 MB answers 422 photo_too_large" do
    big = Rack::Test::UploadedFile.new(StringIO.new(PNG_HEADER + ("\x00".b * ProductPhoto::PHOTO_MAX_SIZE)), "image/png", original_filename: "grande.png")
    put_photo({ file: big })
    assert_response :unprocessable_entity
    assert_equal "photo_too_large", error_code
    assert_not @product.reload.photo.attached?
  end

  test "an unknown style answers 422 invalid_photo_style" do
    put_photo({ file: file, style: "poster" })
    assert_response :unprocessable_entity
    assert_equal "invalid_photo_style", error_code

    put_photo
    patch path, params: { style: "poster" }, headers: @owner
    assert_response :unprocessable_entity
    assert_equal "invalid_photo_style", error_code
  end

  test "PATCH changes only the style, without a new upload" do
    put_photo
    blob = @product.reload.photo.blob

    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) do
      patch path, params: { style: "thumbnail" }, headers: @owner
    end
    assert_response :ok
    assert_equal "thumbnail", response.parsed_body.dig("photo", "style")
    assert_equal blob, @product.reload.photo.blob
  end

  test "PATCH and DELETE without a photo answer 404 photo_not_found" do
    patch path, params: { style: "thumbnail" }, headers: @owner
    assert_response :not_found
    assert_equal "photo_not_found", error_code

    delete path, headers: @owner
    assert_response :not_found
    assert_equal "photo_not_found", error_code
  end

  test "DELETE removes the photo and resets the style" do
    put_photo({ file: file, style: "thumbnail" })
    delete path, headers: @owner
    assert_response :ok
    assert_nil response.parsed_body["photo"]
    @product.reload
    assert_not @product.photo.attached?
    assert_equal "card", @product.photo_style
  end

  test "staff cannot upload, restyle or remove a photo" do
    waiter = auth_headers(users(:resto_waiter), @company)
    put_photo(headers: waiter)
    assert_response :forbidden
    patch path, params: { style: "thumbnail" }, headers: waiter
    assert_response :forbidden
    delete path, headers: waiter
    assert_response :forbidden
  end

  test "a company without the restaurant module answers 403 module_not_in_plan" do
    company = companies(:basic_co)
    type = ProductTypes::Defaults.create_missing(company).find_by!(sellable: true)
    product = company.products.create!(name: "Café", sku: "CAF-1", product_type: type, price: 30)

    put_photo(headers: auth_headers(users(:basic_co_owner), company), product: product)
    assert_response :forbidden
    assert_equal "module_not_in_plan", error_code
  end

  test "a product of another company answers 404" do
    put_photo(product: products(:one))
    assert_response :not_found
  end

  test "the super admin can upload a photo" do
    put_photo(headers: auth_headers(users(:super_admin), @company))
    assert_response :ok
  end
end
