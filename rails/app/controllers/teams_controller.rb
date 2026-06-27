class TeamsController < ApplicationController
  include MatchListData

  def show
    @team = Team.find(params[:id])
    assign_schedule_data(team_matches(@team))
  end

  private

  # The team's full journey: every match it's really in (past and upcoming) plus
  # the undetermined knockout matches it's predicted to reach, all the way to the
  # Final — so a name tap shows both their history and what they play next.
  def team_matches(team)
    predictor = KnockoutPredictor.new
    Match.chronological.includes(:home_team, :away_team)
         .select { |match| team_in_match?(match, team, predictor) }
  end

  def team_in_match?(match, team, predictor)
    return true if [ match.home_team_id, match.away_team_id ].include?(team.id)
    return false unless match.result.nil? && Match.knockout?(match.stage)

    predicted_team?(match.home_label, team, predictor) || predicted_team?(match.away_label, team, predictor)
  end

  def predicted_team?(label, team, predictor)
    return false if label.blank?

    prediction = predictor.predict(label)
    return false unless prediction

    if prediction.kind == :team
      prediction.row&.team_id == team.id
    else
      Array(prediction.candidates).any? { |candidate| candidate.row&.team_id == team.id }
    end
  end
end
