namespace :products do
  desc "Lista los SKU repetidos que solo difieren en mayúsculas o espacios (spec 052); no borra nada"
  task duplicate_skus: :environment do
    groups = Product.group(:company_id, "lower(trim(sku))").having("count(*) > 1").pluck(:company_id, Arel.sql("lower(trim(sku))"))
    if groups.empty?
      puts "Sin SKU repetidos."
    else
      groups.each do |company_id, key|
        skus = Product.where(company_id: company_id).where("lower(trim(sku)) = ?", key).pluck(:id, :sku, :name)
        puts "Empresa #{company_id}: #{skus.map { |id, sku, name| "##{id} #{sku.inspect} (#{name})" }.join(' | ')}"
      end
    end
  end
end
