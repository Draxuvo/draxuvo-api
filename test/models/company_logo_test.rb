require "test_helper"

# Spec 063: logo propio de la empresa (concern CompanyLogo; data-model.md).
class CompanyLogoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FILES = Rails.root.join("test/fixtures/files")
  PNG_HEADER = "\x89PNG\r\n\x1A\n".b

  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
  end

  def upload(name, type)
    Rack::Test::UploadedFile.new(FILES.join(name), type, original_filename: name)
  end

  test "accepts PNG, JPG and WebP and renames the file to logo.<ext>" do
    { "logo.png" => "png", "foto.jpg" => "jpg", "foto.webp" => "webp" }.each do |name, ext|
      type = { "png" => "image/png", "jpg" => "image/jpeg", "webp" => "image/webp" }.fetch(ext)
      @company.attach_logo!(upload(name, type), user: @owner)
      assert_equal "logo.#{ext}", @company.reload.logo.filename.to_s
    end
  end

  test "records who and when it was uploaded" do
    freeze_time do
      @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
      assert_equal @owner, @company.reload.logo_updated_by
      assert_equal Time.current, @company.logo_updated_at
    end
  end

  test "rejects a file that is not JPG, PNG or WebP by its content, keeping the previous logo" do
    @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    previous = @company.reload.logo.blob

    error = assert_raises(ActiveRecord::RecordInvalid) do
      @company.attach_logo!(upload("foto.heic", "image/png"), user: @owner)
    end
    assert_equal :invalid_type, error.record.errors.details[:logo].first[:error]
    assert_equal previous, @company.reload.logo.blob
  end

  test "rejects a logo over 5 MB" do
    big = Rack::Test::UploadedFile.new(StringIO.new(PNG_HEADER + ("\x00".b * CompanyLogo::LOGO_MAX_SIZE)), "image/png", original_filename: "grande.png")
    error = assert_raises(ActiveRecord::RecordInvalid) { @company.attach_logo!(big, user: @owner) }
    assert_equal :too_large, error.record.errors.details[:logo].first[:error]
    assert_not @company.reload.logo.attached?
  end

  test "replacing the logo purges the previous one" do
    @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    first = @company.reload.logo.blob
    perform_enqueued_jobs { @company.attach_logo!(upload("foto.jpg", "image/jpeg"), user: @owner) }
    assert_not ActiveStorage::Blob.exists?(first.id)
    assert_equal "logo.jpg", @company.reload.logo.filename.to_s
  end

  test "remove_logo! purges it and records who and when" do
    @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    admin = create_member(@company, role: :admin)
    freeze_time do
      perform_enqueued_jobs { @company.remove_logo!(user: admin) }
      assert_not @company.reload.logo.attached?
      assert_equal admin, @company.logo_updated_by
      assert_equal Time.current, @company.logo_updated_at
    end
  end

  test "without a logo every url and the payload are nil" do
    assert_nil @company.logo_redirect_url
    assert_nil @company.logo_public_url
    assert_nil @company.logo_payload
    assert_nil @company.logo_print_io
  end

  test "the redirect url points to the display variant and the public url waits until it is ready" do
    @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    assert_match %r{/rails/active_storage/representations/redirect/}, @company.logo_redirect_url
    assert_nil @company.logo_public_url

    perform_enqueued_jobs
    @company.reload
    assert @company.logo_ready?
    ActiveStorage::Current.set(url_options: { host: "example.com" }) do
      assert_match %r{logo\.webp}, @company.logo_public_url
    end
  end

  test "the payload carries url, date and who changed it" do
    @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    payload = @company.reload.logo_payload
    assert_equal @company.logo_redirect_url, payload[:url]
    assert_equal({ id: @owner.id, name: @owner.full_name }, payload[:updated_by])
    assert_not_nil payload[:updated_at]
  end

  test "the print version is a PNG without cropping a wide logo" do
    @company.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    io = @company.reload.logo_print_io
    assert io
    assert_equal PNG_HEADER, io.read(8)
  end

  test "a branch does not inherit the logo of its main company (FR-011)" do
    main = companies(:enterprise_co)
    branch = Company.create!(name: "Sucursal Logo", parent: main)
    main.attach_logo!(upload("logo.png", "image/png"), user: @owner)
    assert_not branch.reload.logo.attached?
    assert_nil branch.logo_redirect_url
  end
end
