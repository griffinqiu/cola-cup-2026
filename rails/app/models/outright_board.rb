# Builds the per-candidate view rows for a prediction market: the subject, its
# yes/no pool tally, the viewer's own pick, and (once settled) the subject's
# outcome and the viewer's ledger entry. Shared by PredictionsController and
# OutrightPicksController so a single card renders the same everywhere.
class OutrightBoard
  # `prob` is the Polymarket champion probability (0..1, nil if unmatched/absent);
  # golden boot has none. Champion rows are ordered by it; golden boot keeps the
  # goals order from Scorers.ranked.
  Row = Struct.new(:subject, :tally, :my_pick, :my_stake, :my_entry, :outcome, :prob, :roster,
                   :open, :deadline, keyword_init: true)

  def self.driver(market)
    market == GoldenBoot::MARKET ? GoldenBoot : Champion
  end

  def initialize(market, user)
    @market = market
    @user = user
  end

  def rows
    build(self.class.driver(@market).candidate_subjects)
  end

  def row(subject)
    build([ subject ]).first
  end

  private

  def build(subjects)
    tallies = OutrightPick.tallies_for(@market)
    my_picks = @user ? @user.outright_picks.where(market: @market).index_by(&:subject_key) : {}
    my_entries = @user ? @user.outright_ledger_entries.where(market: @market).index_by(&:subject_key) : {}
    outcomes = OutrightLedgerEntry.for_market(@market).distinct.pluck(:subject_key, :outcome).to_h
    live_probs = @market == Champion::MARKET ? Polymarket::ChampionOdds.probabilities : {}
    rosters = OutrightPick.active.where(market: @market).includes(:user)
                          .order(:updated_at).group_by(&:subject_key)
    # Frozen prob snapshot, written per team at its own lock (odds freeze at 封盘).
    frozen = OutrightCandidate.for_market(@market).index_by(&:subject_key)
    deadlines = Champion.deadlines_by_team
    now = Time.current

    rows = subjects.map do |subject|
      mine = my_picks[subject.subject_key]
      outcome = outcomes[subject.subject_key]
      deadline = deadlines[subject.team_id]
      Row.new(
        subject: subject,
        tally: tallies[subject.subject_key] || OutrightPick.empty_tally,
        my_pick: mine&.pick,
        my_stake: mine&.stake,
        my_entry: my_entries[subject.subject_key],
        outcome: outcome,
        prob: frozen[subject.subject_key]&.meta&.dig("prob") || live_probs[subject.team_id],
        roster: rosters[subject.subject_key] || [],
        open: outcome.nil? && deadline.present? && now < deadline,
        deadline: deadline
      )
    end

    order_rows(rows)
  end

  # Eliminated candidates (settled "lost") are never dropped — they sink to the
  # bottom. Above them: champion by Polymarket probability (unmatched last),
  # golden boot by its incoming goals order. Ties keep the incoming order.
  def order_rows(rows)
    rows.each_with_index.sort_by do |row, index|
      market_key = @market == Champion::MARKET ? (row.prob ? -row.prob : 1.0) : index
      [ eliminated_rank(row), market_key, index ]
    end.map(&:first)
  end

  def eliminated_rank(row)
    row.outcome == "lost" ? 1 : 0
  end
end
