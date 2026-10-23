module Products
  # Corre una importación de productos en segundo plano (spec 034): avanza por lotes, deja el resumen en la
  # fila de `ProductImport` y borra el archivo al terminar.
  class ImportJob < ApplicationJob
    queue_as :default

    def perform(import_id)
      import = ProductImport.find_by(id: import_id)
      return unless import&.queued?

      import.update!(status: :processing, started_at: Time.current)
      run(import)
    rescue StandardError => e
      fail_import(import, e) if import
    end

    private

    def run(import)
      extension = File.extname(import.filename.to_s).presence || ".xlsx"
      Tempfile.create([ "import-#{import.id}", extension ]) do |file|
        file.binmode
        file.write(import.file_data)
        file.flush
        upload = Struct.new(:path, :original_filename).new(file.path, import.filename.to_s)
        result = ImportService.new(import.company, upload, allow_icon: import.allow_icon, user: import.user,
                                   on_progress: ->(partial) { save_progress(import, partial) }).call
        save_progress(import, result)
      end
      import.update!(status: :done, finished_at: Time.current, file_data: nil)
    end

    def save_progress(import, result)
      import.update!(processed_rows: result.processed, created_count: result.created, updated_count: result.updated,
                     unchanged_count: result.unchanged, errors_list: result.errors.map(&:stringify_keys),
                     errors_total: result.errors_total)
    end

    def fail_import(import, error)
      Rails.logger.error("[ProductImport ##{import.id}] #{error.class}: #{error.message}")
      import.reload
      import.update!(status: :failed, finished_at: Time.current, file_data: nil,
                     errors_list: import.errors_list + [ { "row" => nil, "error" => error.message } ])
    end
  end
end
