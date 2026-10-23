class ProductImportSerializer
  def initialize(import)
    @import = import
  end

  def as_json(*)
    {
      id: @import.id,
      status: @import.status,
      filename: @import.filename,
      total_rows: @import.total_rows,
      processed_rows: @import.processed_rows,
      created: @import.created_count,
      updated: @import.updated_count,
      unchanged: @import.unchanged_count,
      errors: @import.errors_list,
      errors_total: @import.errors_total,
      started_at: @import.started_at,
      finished_at: @import.finished_at,
      created_at: @import.created_at,
      user: @import.user && { id: @import.user.id, name: @import.user.full_name }
    }
  end
end
