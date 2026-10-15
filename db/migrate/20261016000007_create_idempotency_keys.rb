class CreateIdempotencyKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :idempotency_keys do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :key, null: false, limit: 64
      t.string :request_method, null: false
      t.string :request_path, null: false
      t.integer :response_status, null: false
      t.text :response_body, null: false
      t.timestamps
    end

    add_index :idempotency_keys, %i[user_id key], unique: true
    add_index :idempotency_keys, :created_at
  end
end
