require "rails_helper"

RSpec.describe KnockoutResolver do
  def finished(home, away, home_score, away_score, group)
    result = { 1 => "home", 0 => "draw", -1 => "away" }[home_score <=> away_score]
    create(:match, stage: "group", group_name: group,
      home_team: home, away_team: away,
      home_score: home_score, away_score: away_score,
      result: result, result_at: Time.current, settled: true)
  end

  # A 3-team group, all matches played, ranked first > second > third.
  # `third_concedes` widens the third team's goals-against to set its cross-group rank.
  def group_with(letter, third_concedes: 1)
    first = create(:team, name: "#{letter}-1st")
    second = create(:team, name: "#{letter}-2nd")
    third = create(:team, name: "#{letter}-3rd")
    name = "Group #{letter}"
    finished(first, second, 1, 0, name)
    finished(first, third, 1, 0, name)
    finished(second, third, third_concedes, 0, name)
    { first: first, second: second, third: third }
  end

  def ko(num, **attrs)
    create(:match, **{ group_name: nil, home_team: nil, away_team: nil,
      external_key: "m:#{num}" }.merge(attrs))
  end

  describe "winner/loser propagation" do
    it "fills a W## slot with the source match winner" do
      home = create(:team)
      away = create(:team)
      ko(74, stage: "r32", home_team: home, away_team: away,
        result: "home", home_score: 2, away_score: 1, result_at: Time.current)
      slot = ko(89, stage: "r16", home_label: "W74", away_label: "W77")

      KnockoutResolver.run

      slot.reload
      expect(slot.home_team_id).to eq(home.id)
      expect(slot.away_team_id).to be_nil # W77 source absent
    end

    it "fills an L## third-place slot with the source match loser" do
      home = create(:team)
      away = create(:team)
      ko(101, stage: "sf", home_team: home, away_team: away,
        result: "home", home_score: 1, away_score: 0, result_at: Time.current)
      slot = ko(103, stage: "third", home_label: "L101", away_label: "L102")

      KnockoutResolver.run

      expect(slot.reload.home_team_id).to eq(away.id) # loser of m101
    end

    it "leaves a winner slot unresolved while its source has no result" do
      ko(74, stage: "r32", home_team: create(:team), away_team: create(:team))
      slot = ko(89, stage: "r16", home_label: "W74", away_label: "W77")

      KnockoutResolver.run

      expect(slot.reload.home_team_id).to be_nil
    end
  end

  describe "R32 group positions" do
    it "fills 1A/2A once the group is fully played" do
      teams = group_with("A")
      slot = ko(73, stage: "r32", home_label: "1A", away_label: "2A")

      KnockoutResolver.run

      slot.reload
      expect(slot.home_team_id).to eq(teams[:first].id)
      expect(slot.away_team_id).to eq(teams[:second].id)
    end

    it "leaves a position slot unresolved while the group has an unplayed match" do
      group_with("A")
      create(:match, stage: "group", group_name: "Group A",
        home_team: create(:team), away_team: create(:team), result: nil, settled: false)
      slot = ko(73, stage: "r32", home_label: "1A", away_label: "2A")

      KnockoutResolver.run

      expect(slot.reload.home_team_id).to be_nil
    end
  end

  describe "R32 best-third slots (FIFA Annex C)" do
    it "fills each third-place slot once every group is complete" do
      letters = %w[A B C D E F G H I J K L]
      groups = letters.each_with_index.to_h { |l, i| [ l, group_with(l, third_concedes: i + 1) ] }
      match_order = [ 74, 77, 79, 80, 81, 82, 85, 87 ]
      slot_labels = %w[3A/B/C/D/F 3C/D/F/G/H 3C/E/F/H/I 3E/H/I/J/K 3B/E/F/I/J 3A/E/H/I/J 3E/F/G/I/J 3D/E/I/J/L]
      slots = slot_labels.each_with_index.map do |label, i|
        ko(match_order[i], stage: "r32", home_label: "1#{letters[i]}", away_label: label)
      end

      KnockoutResolver.run

      # Official Annex C row for ABCDEFGH = CFHEBAGD over 74/77/79/80/81/82/85/87.
      expected = %w[C F H E B A G D]
      slots.each_with_index do |slot, i|
        slot.reload
        expect(slot.away_team_id).to eq(groups[expected[i]][:third].id)
        expect(slot.home_team_id).to eq(groups[letters[i]][:first].id)
      end
    end

    it "leaves third-place slots unresolved until every group is complete" do
      letters = %w[A B C D E F G H I J K L]
      groups = letters.each_with_index.to_h { |l, i| [ l, group_with(l, third_concedes: i + 1) ] }
      create(:match, stage: "group", group_name: "Group A",
        home_team: create(:team), away_team: create(:team), result: nil, settled: false)
      slot = ko(74, stage: "r32", home_label: "1E", away_label: "3A/B/C/D/F")

      KnockoutResolver.run

      slot.reload
      expect(slot.away_team_id).to be_nil # third-place needs all groups complete
      expect(slot.home_team_id).to eq(groups["E"][:first].id) # but 1E resolvable (group E done)
    end
  end

  describe "chaining and safety" do
    it "resolves R32 then R16 in a single pass" do
      a = group_with("A")
      group_with("B")
      ko(73, stage: "r32", home_label: "1A", away_label: "2B",
        result: "home", home_score: 1, away_score: 0, result_at: Time.current)
      slot = ko(89, stage: "r16", home_label: "W73", away_label: "W74")

      KnockoutResolver.run

      # m73 resolves to A-1st vs B-2nd; result home -> winner A-1st feeds W73.
      expect(slot.reload.home_team_id).to eq(a[:first].id)
    end

    it "never overwrites a side that already holds a team" do
      teams = group_with("A")
      fixed = create(:team)
      slot = ko(73, stage: "r32", home_team: fixed, home_label: "1A", away_label: "2A")

      KnockoutResolver.run

      slot.reload
      expect(slot.home_team_id).to eq(fixed.id)
      expect(slot.away_team_id).to eq(teams[:second].id)
    end

    it "is idempotent" do
      group_with("A")
      ko(73, stage: "r32", home_label: "1A", away_label: "2A")

      expect(KnockoutResolver.run).to eq(1)
      expect(KnockoutResolver.run).to eq(0)
    end

    it "writes only team ids, never result/score/settled" do
      home = create(:team)
      away = create(:team)
      ko(74, stage: "r32", home_team: home, away_team: away,
        result: "home", home_score: 2, away_score: 1, result_at: Time.current)
      slot = ko(89, stage: "r16", home_label: "W74", away_label: "W77")

      KnockoutResolver.run

      slot.reload
      expect(slot.result).to be_nil
      expect(slot.home_score).to be_nil
      expect(slot.settled).to be(false)
    end
  end
end
