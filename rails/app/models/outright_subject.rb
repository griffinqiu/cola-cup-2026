# A bettable subject in an outright market — a team (champion) or a player
# (golden boot). A plain value object so the page renders candidate cards
# uniformly whether the field is live (pre-lock) or read from the frozen
# OutrightCandidate snapshot (post-lock).
OutrightSubject = Struct.new(:market, :subject_key, :subject_label, :team, :meta, keyword_init: true) do
  def team_id
    team&.id || meta&.dig("team_id")
  end

  # Name shown on the candidate card. Champion subjects ARE teams, so their name
  # must follow the locale (subject_label is the frozen Chinese name kept for
  # settlement records). Golden boot subjects are players — names aren't localized.
  def display_label
    market == Champion::MARKET && team ? team.display_name : subject_label
  end
end
