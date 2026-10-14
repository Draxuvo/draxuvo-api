class AddCancelAtPeriodEndAndLookupKeyToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :cancel_at_period_end, :boolean, default: false, null: false
    add_column :subscriptions, :stripe_price_lookup_key, :string
  end
end
