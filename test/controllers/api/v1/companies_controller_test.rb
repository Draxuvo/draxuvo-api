require "test_helper"

# Spec 044 (FR-009): el alta de una empresa dice por qué falla, no responde 422 con details vacío.
class Api::V1::CompaniesControllerTest < ActionDispatch::IntegrationTest
  def as_super_admin = auth_headers(users(:super_admin), nil)

  def json = JSON.parse(response.body)

  test "creates the company even when the units table is empty" do
    Unit.delete_all

    assert_difference -> { Company.count } => 1, -> { Subscription.count } => 1 do
      post "/api/v1/companies", params: { company: { name: "Aquí me quedo", active: false } }, headers: as_super_admin, as: :json
    end

    assert_response :created
    assert_equal Unit::CATALOG.size, Unit.count
    assert_equal 3, Company.find(json["id"]).product_types.count
  end

  test "a repeated slug answers 422 with the reason" do
    post "/api/v1/companies", params: { company: { name: companies(:one).name } }, headers: as_super_admin, as: :json

    assert_response :unprocessable_entity
    assert_includes json.dig("error", "details"), "Slug ya está en uso"
  end

  test "a failure inside the after_create names the record that failed and saves nothing" do
    broken = ->(_company) { ProductType.create!(company: companies(:one), name: "") }

    assert_no_difference [ "Company.count", "Subscription.count" ] do
      ProductTypes::Defaults.stub :create_missing, broken do
        post "/api/v1/companies", params: { company: { name: "Falla Adentro" } }, headers: as_super_admin, as: :json
      end
    end

    assert_response :unprocessable_entity
    assert json.dig("error", "details").any?, "details no debe ir vacío"
  end

  test "only the super admin creates companies" do
    owner = create_member(companies(:one), role: :owner)
    post "/api/v1/companies", params: { company: { name: "Otra" } }, headers: auth_headers(owner), as: :json
    assert_response :forbidden
  end

  # Spec 063 (US3): el super admin ve el logo de cada empresa en la lista.
  test "the list carries the logo of each company, or null" do
    company = companies(:resto_co)
    file = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/logo.png"), "image/png", original_filename: "logo.png")
    company.attach_logo!(file, user: users(:resto_owner))

    get "/api/v1/companies", params: { page_size: 100 }, headers: as_super_admin
    assert_response :ok
    rows = json["results"].index_by { |c| c["id"] }
    assert_match %r{/rails/active_storage/representations/redirect/}, rows[company.id].dig("logo", "url")
    assert_equal users(:resto_owner).id, rows[company.id].dig("logo", "updated_by", "id")
    assert_nil rows[companies(:pro_co).id]["logo"]
  end
end
