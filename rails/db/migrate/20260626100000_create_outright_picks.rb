class CreateOutrightPicks < ActiveRecord::Migration[8.1]
  def change
    create_table :outright_picks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :market, null: false
      t.string :subject_key, null: false
      t.string :subject_label, null: false
      t.references :team, foreign_key: { to_table: :teams }
      t.string :pick, null: false
      t.float :stake, null: false, default: 1.0
      t.timestamps
    end

    add_index :outright_picks, [ :user_id, :market, :subject_key ], unique: true
    add_index :outright_picks, [ :market, :subject_key ]
  end
end
