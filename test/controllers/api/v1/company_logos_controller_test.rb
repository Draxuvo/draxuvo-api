require "test_helper"

# Spec 063: PUT y DELETE /api/v1/company/logo (contracts/api.md).
class Api::V1::CompanyLogosControllerTest < ActionDispatch::IntegrationTest
  FILES = Rails.root.join("test/fixtures/files")
  PNG_HEADER = "\x89PNG\r\n\x1A\n".b
  PATH = "/api/v1/company/logo".freeze

  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
  end

  def file(name = "logo.png", type = "image/png")
    Rack::Test::UploadedFile.new(FILES.join(name), type, original_filename: name)
  end

  def put_logo(user, company = @company, params: { file: file })
    put PATH, params: params, headers: auth_headers(user, company)
  end

  def error_code = response.parsed_body.dig("error", "details", "code")

  test "the owner uploads the logo and gets it back with who changed it" do
    put_logo(@owner)
    assert_response :ok
    logo = response.parsed_body["logo"]
    assert_match %r{/rails/active_storage/representations/redirect/}, logo["url"]
    assert_equal @owner.id, logo.dig("updated_by", "id")
    assert @company.reload.logo.attached?
    assert_equal "logo.png", @company.logo.filename.to_s
  end

  test "an admin can upload and remove it" do
    admin = create_member(@company, role: :admin)
    put_logo(admin)
    assert_response :ok

    delete PATH, headers: auth_headers(admin, @company)
    assert_response :ok
    assert_nil response.parsed_body["logo"]
    assert_not @company.reload.logo.attached?
    assert_equal admin, @company.logo_updated_by
  end

  test "staff gets 403 and nothing changes" do
    put_logo(users(:resto_waiter))
    assert_response :forbidden
    assert_not @company.reload.logo.attached?

    @company.attach_logo!(file, user: @owner)
    delete PATH, headers: auth_headers(users(:resto_waiter), @company)
    assert_response :forbidden
    assert @company.reload.logo.attached?
  end

  test "the super admin changes the logo of the company in X-Company-Id" do
    put_logo(users(:super_admin), @company)
    assert_response :ok
    assert @company.reload.logo.attached?
    assert_equal users(:super_admin), @company.logo_updated_by
  end

  test "the logo belongs to the company in X-Company-Id only" do
    other = companies(:pro_co)
    put_logo(users(:pro_co_owner), other)
    assert_response :ok
    assert other.reload.logo.attached?
    assert_not @company.reload.logo.attached?
  end

  test "without a file answers 422 logo_missing" do
    put_logo(@owner, params: {})
    assert_response :unprocessable_entity
    assert_equal "logo_missing", error_code
  end

  test "a file that is not JPG, PNG or WebP answers 422 logo_invalid_type and keeps the previous logo" do
    @company.attach_logo!(file, user: @owner)
    previous = @company.reload.logo.blob
    put_logo(@owner, params: { file: file("foto.heic", "image/png") })
    assert_response :unprocessable_entity
    assert_equal "logo_invalid_type", error_code
    assert_equal previous, @company.reload.logo.blob
  end

  test "a logo over 5 MB answers 422 logo_too_large" do
    big = Rack::Test::UploadedFile.new(StringIO.new(PNG_HEADER + ("\x00".b * CompanyLogo::LOGO_MAX_SIZE)), "image/png", original_filename: "grande.png")
    put_logo(@owner, params: { file: big })
    assert_response :unprocessable_entity
    assert_equal "logo_too_large", error_code
    assert_not @company.reload.logo.attached?
  end

  test "removing when there is no logo answers 404 logo_not_found" do
    delete PATH, headers: auth_headers(@owner, @company)
    assert_response :not_found
    assert_equal "logo_not_found", error_code
  end

  test "a suspended company cannot change its logo" do
    subscriptions(:pro_co).update!(status: :suspended, suspended_at: Time.current, suspension_reason: "plan_change")
    put_logo(users(:pro_co_owner), companies(:pro_co))
    assert_response :forbidden
    assert_equal "subscription_suspended", error_code
    assert_not companies(:pro_co).reload.logo.attached?
  end

  test "the session carries the new logo after uploading it" do
    put_logo(@owner)
    get "/api/v1/auth/me", headers: auth_headers(users(:resto_waiter), @company)
    assert_response :ok
    company = response.parsed_body.dig("user", "companies").find { |c| c["id"] == @company.id }
    assert_match %r{/rails/active_storage/representations/redirect/}, company["logo_url"]
  end

  # US4 (FR-011): cada sucursal con su logo; la principal no cambia.
  test "a branch gets its own logo and the main company keeps its own" do
    main = companies(:enterprise_co)
    owner = create_member(main, role: :owner)
    branch = Company.create!(name: "Sucursal Logo", parent: main)
    UserCompany.create!(user: owner, company: branch, role: :owner)

    put_logo(owner, branch)
    assert_response :ok
    assert branch.reload.logo.attached?
    assert_not main.reload.logo.attached?

    get "/api/v1/auth/me", headers: auth_headers(owner, branch)
    companies = response.parsed_body.dig("user", "companies").index_by { |c| c["id"] }
    assert companies[branch.id]["logo_url"].present?
    assert_nil companies[main.id]["logo_url"]
  end
end
