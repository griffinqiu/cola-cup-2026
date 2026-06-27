class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  # Persists each user's preferred UI language. Defaults to the app default
  # (Simplified Chinese) so existing rows keep rendering exactly as before.
  def change
    add_column :users, :locale, :string, null: false, default: "zh-CN"
  end
end
