FactoryBot.define do
  factory :outright_pick do
    user
    market { "champion" }
    sequence(:subject_key) { |n| "team:#{n}" }
    subject_label { "球队" }
    pick { "yes" }
    stake { 1.0 }
  end
end
