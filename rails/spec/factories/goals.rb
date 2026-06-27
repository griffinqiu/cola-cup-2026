FactoryBot.define do
  factory :goal do
    match
    association :team, factory: :team
    sequence(:player_name) { |n| "Player #{n}" }
    minute { 50 }
    penalty { false }
    own_goal { false }
  end
end
