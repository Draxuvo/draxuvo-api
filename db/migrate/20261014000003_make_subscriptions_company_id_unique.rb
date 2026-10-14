class MakeSubscriptionsCompanyIdUnique < ActiveRecord::Migration[8.0]
  def change
    remove_index :subscriptions, :company_id
    add_index :subscriptions, :company_id, unique: true
  end
end
