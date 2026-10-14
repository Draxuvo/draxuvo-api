class AddAppearanceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :theme, :string, null: false, default: "anaquel"
    add_column :users, :color_mode, :string, null: false, default: "system"
  end
end
