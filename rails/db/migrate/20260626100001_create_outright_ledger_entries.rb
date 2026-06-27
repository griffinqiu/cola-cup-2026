class CreateOutrightLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :outright_ledger_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.string :market, null: false
      t.string :subject_key, null: false
      t.string :subject_label, null: false
      t.references :team, foreign_key: { to_table: :teams }
      t.string :pick, null: false
      t.float :stake, null: false
      t.float :d_used, null: false
      t.boolean :won, null: false
      t.float :delta, null: false
      t.string :outcome, null: false
      t.references :source_match, foreign_key: { to_table: :matches }
      t.references :settled_by, foreign_key: { to_table: :users }
      t.datetime :settled_at, null: false
      t.timestamps
    end

    add_index :outright_ledger_entries, [ :user_id, :market, :subject_key ], unique: true
    add_index :outright_ledger_entries, [ :market, :subject_key ]
  end
end
