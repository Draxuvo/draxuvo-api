require "test_helper"

class Products::ImportJobTest < ActiveJob::TestCase
  setup do
    @company = companies(:resto_co)
    @user = users(:resto_owner)
  end

  def import_with(csv, filename: "catalogo.csv")
    @company.product_imports.create!(user: @user, filename: filename, total_rows: csv.lines.size - 1, file_data: csv)
  end

  test "runs the import, leaves the summary and clears the file" do
    import = import_with("sku,name,barcodes\nJ-1,Uno,9200000000001\nJ-2,Dos,\n,Sin sku,\n")

    Products::ImportJob.perform_now(import.id)
    import.reload

    assert import.done?
    assert_equal [ 2, 0, 0, 3 ], [ import.created_count, import.updated_count, import.unchanged_count, import.processed_rows ]
    assert_equal 1, import.errors_total
    assert_equal 4, import.errors_list.first["row"]
    assert_nil import.file_data
    assert_not_nil import.started_at
    assert_not_nil import.finished_at
    assert_equal [ "9200000000001" ], @company.products.find_by!(sku: "J-1").barcode_codes
  end

  test "a file that cannot be read leaves the import failed with the reason and no file" do
    import = import_with("x", filename: "datos.pdf")

    Products::ImportJob.perform_now(import.id)
    import.reload

    assert import.failed?
    assert_nil import.file_data
    assert import.errors_list.last["error"].present?
  end

  test "only a queued import is processed" do
    import = import_with("sku,name\nK-1,Uno\n")
    import.update!(status: :done)

    assert_no_difference -> { @company.products.count } do
      Products::ImportJob.perform_now(import.id)
    end
  end

  test "a missing import is ignored" do
    assert_nothing_raised { Products::ImportJob.perform_now(0) }
  end

  test "an import that stalls while processing is marked failed when checked" do
    import = import_with("sku,name\n")
    import.update_columns(status: ProductImport.statuses[:processing], updated_at: 20.minutes.ago)

    ProductImport.fail_stale!

    assert import.reload.failed?
    assert_nil import.file_data
    assert_equal I18n.t("products.import.interrupted"), import.errors_list.last["error"]
  end

  test "a recent processing import is left alone" do
    import = import_with("sku,name\n")
    import.update_columns(status: ProductImport.statuses[:processing], updated_at: 1.minute.ago)

    ProductImport.fail_stale!

    assert import.reload.processing?
  end
end
