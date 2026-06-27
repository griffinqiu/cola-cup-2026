FactoryBot.define do
  factory :outright_ledger_entry do
    user
    market { "champion" }
    sequence(:subject_key) { |n| "team:#{n}" }
    subject_label { "球队" }
    pick { "yes" }
    stake { 1.0 }
    d_used { 2.0 }
    won { true }
    delta { 1.0 }
    outcome { "won_title" }
    settled_at { Time.current }
  end
end
