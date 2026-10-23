require "test_helper"

class Api::V1::ProductImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = companies(:resto_co)
    @owner = auth_headers(users(:resto_owner), @company)
    @waiter = auth_headers(users(:resto_waiter), @company)
  end

  def upload(csv, name: "catalogo.csv", headers: @owner)
    Tempfile.create([ "up", File.extname(name) ]) do |file|
      file.write(csv)
      file.flush
      post "/api/v1/products/import", params: { file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: name) }, headers: headers
    end
  end

  test "uploading answers 202 with the import, enqueues the job and keeps the file" do
    assert_enqueued_with(job: Products::ImportJob) do
      upload("sku,name\nA-1,Uno\nA-2,Dos\n")
    end

    assert_response :accepted
    body = response.parsed_body
    assert_equal %w[queued catalogo.csv], [ body["status"], body["filename"] ]
    assert_equal [ 2, 0 ], [ body["total_rows"], body["processed_rows"] ]
    assert_equal users(:resto_owner).full_name, body.dig("user", "name")
    assert_not_nil ProductImport.find(body["id"]).file_data
  end

  test "any member can import, and the job applies the file" do
    upload("sku,name,barcodes\nW-1,Mesero,9300000000001\n", headers: @waiter)
    assert_response :accepted

    perform_enqueued_jobs
    get "/api/v1/product_imports/#{response.parsed_body['id']}", headers: @waiter

    assert_equal "done", response.parsed_body["status"]
    assert_equal 1, response.parsed_body["created"]
    assert @company.products.exists?(sku: "W-1")
  end

  test "only admins and owners apply icons from the file" do
    upload("sku,name,icon\nI-W,Mesero,taco\n", headers: @waiter)
    perform_enqueued_jobs
    assert_nil @company.products.find_by!(sku: "I-W").icon

    upload("sku,name,icon\nI-O,Dueño,taco\n", headers: @owner)
    perform_enqueued_jobs
    assert_equal "taco", @company.products.find_by!(sku: "I-O").icon
  end

  test "a second upload while one is active answers 409 with the active import" do
    upload("sku,name\nA-1,Uno\n")
    first_id = response.parsed_body["id"]

    upload("sku,name\nB-1,Otro\n")

    assert_response :conflict
    assert_equal "import_in_progress", response.parsed_body.dig("error", "details", "code")
    assert_equal first_id, response.parsed_body.dig("error", "details", "import", "id")
  end

  test "validates the file before queueing anything" do
    post "/api/v1/products/import", headers: @owner
    assert_response :bad_request
    assert_equal "file_required", response.parsed_body.dig("error", "details", "code")

    upload("x", name: "datos.pdf")
    assert_response :unprocessable_entity
    assert_equal "unsupported_format", response.parsed_body.dig("error", "details", "code")

    stub_const_max_rows(2) do
      upload("sku,name\nA,1\nB,2\nC,3\n")
      assert_response :unprocessable_entity
      assert_equal "too_many_rows", response.parsed_body.dig("error", "details", "code")
    end
    assert_equal 0, ProductImport.count
  end

  test "show and index are scoped to the company and active filters the running ones" do
    upload("sku,name\nA-1,Uno\n")
    mine = response.parsed_body["id"]
    other = companies(:one).product_imports.create!(user: users(:resto_owner), filename: "otra.csv", total_rows: 1, file_data: "x")

    get "/api/v1/product_imports/#{other.id}", headers: @owner
    assert_response :not_found

    get "/api/v1/product_imports", headers: @owner
    assert_equal [ mine ], response.parsed_body["results"].map { |i| i["id"] }

    perform_enqueued_jobs
    get "/api/v1/product_imports", params: { active: "true" }, headers: @owner
    assert_empty response.parsed_body["results"]
  end

  test "a company with the inventory module turned off is refused" do
    @company.update!(disabled_modules: [ "inventory" ])

    get "/api/v1/product_imports", headers: @owner
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")

    upload("sku,name\nA,1\n")
    assert_response :forbidden
  end

  private

  def stub_const_max_rows(value)
    original = ProductImport::MAX_ROWS
    ProductImport.send(:remove_const, :MAX_ROWS)
    ProductImport.const_set(:MAX_ROWS, value)
    yield
  ensure
    ProductImport.send(:remove_const, :MAX_ROWS)
    ProductImport.const_set(:MAX_ROWS, original)
  end
end
