# Spec 061: foto opcional del producto para el menú QR. La foto vive en Active Storage (`has_one_attached :photo`);
# aquí solo el estilo con que sale en el menú y quién la subió o cambió.
class AddPhotoToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :photo_style, :string, null: false, default: "card"
    add_reference :products, :photo_updated_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
    add_check_constraint :products, "photo_style IN ('card', 'thumbnail')", name: "products_photo_style_check"
  end
end
