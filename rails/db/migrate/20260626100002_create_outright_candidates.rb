class CreateOutrightCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :outright_candidates do |t|
      t.string :market, null: false
      t.string :subject_key, null: false
      t.string :subject_label, null: false
      t.references :team, foreign_key: { to_table: :teams }
      t.json :meta
      t.datetime :frozen_at, null: false
      t.timestamps
    end

    add_index :outright_candidates, [ :market, :subject_key ], unique: true
  end
end
