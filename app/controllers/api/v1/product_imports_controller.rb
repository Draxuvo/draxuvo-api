module Api
  module V1
    # Importaciones de productos de la empresa (spec 034): estado, avance y resumen guardado.
    class ProductImportsController < BaseController
      requires_module :inventory

      def index
        ProductImport.fail_stale!
        imports = current_company.product_imports.includes(:user).recent
        imports = imports.active if params[:active] == "true"
        @pagy, @imports = pagy(imports)
        render json: paginate_response(@pagy, @imports.map { |import| ProductImportSerializer.new(import).as_json })
      end

      def show
        ProductImport.fail_stale!
        import = current_company.product_imports.includes(:user).find(params[:id])
        render json: ProductImportSerializer.new(import).as_json
      end
    end
  end
end
