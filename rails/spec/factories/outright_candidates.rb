FactoryBot.define do
  factory :outright_candidate do
    market { "golden_boot" }
    sequence(:subject_key) { |n| "scorer:#{n}:Player" }
    subject_label { "Player" }
    meta { {} }
    frozen_at { Time.current }
  end
end
