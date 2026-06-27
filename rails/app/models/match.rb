class Match < ApplicationRecord
  # Raised by the mutating helpers with a Chinese, player-facing message; the
  # admin controllers rescue it to render the error verbatim.
  DomainError = Class.new(StandardError)

  STAGES = %w[group r32 r16 qf sf third final].freeze
  KNOCKOUT_STAGES = %w[r32 r16 qf sf third final].to_set.freeze
  PICKS = %w[home draw away].freeze

  # Stake options per stage, in bottles of coke. Group stays a fixed 1-bottle
  # ante (many matches a week); the knockout rounds let the player choose how
  # much to risk, with the bet rising through the bracket. Single source of
  # truth for both validation and the picker UI.
  STAKE_OPTIONS_BY_STAGE = {
    "group" => [ 1.0 ],
    "r32" => [ 2.0, 3.0 ], "r16" => [ 2.0, 3.0 ], "qf" => [ 2.0, 3.0 ],
    "sf" => [ 3.0, 5.0 ], "third" => [ 3.0, 5.0 ], "final" => [ 3.0, 5.0 ]
  }.freeze

  # Voting opens by calendar day (Beijing midnight), not kickoff-minus-7-days:
  # a match is votable from 00:00 of the 6th day before its kickoff date, so on
  # any morning the whole rolling 7-day slate (today .. day+6) is open at once.
  VOTE_OPENS_DAYS_AHEAD = 7
  VOTE_CLOSES_BEFORE = 1.hour  # voting closes one hour before kickoff

  # A match counts as in play from kickoff until its final result is recorded,
  # capped at this window so a fixture whose result entry lags — or one that was
  # cancelled and never reports FINISHED — doesn't stay "live" forever. Sized to
  # cover 90' + ET + penalties + stoppage/VAR with margin; past it the match
  # needs manual settlement via the admin score entry.
  LIVE_WINDOW = 6.hours

  belongs_to :home_team, class_name: "Team", optional: true
  belongs_to :away_team, class_name: "Team", optional: true
  belongs_to :settlement, optional: true

  has_many :votes, dependent: :destroy
  has_many :ledger_entries, dependent: :destroy
  has_many :odds_snapshots, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_one :poly_market, dependent: :destroy

  validates :external_key, presence: true, uniqueness: true
  validates :stage, presence: true, inclusion: { in: STAGES }
  validates :kickoff_at, presence: true

  scope :chronological, -> { order(:kickoff_at, :id) }
  # Admin "待结算" list: kicked-off matches not yet settled (the result/score may
  # still be blank — the settler records it from this list before settling).
  scope :settle_todo, ->(now = Time.current) {
    where(settled: false).where(kickoff_at: ..now).chronological
  }
  # Matches whose voting window has closed (within 1h of kickoff) and that are
  # not yet settled — the LockDueMatchesJob freezes their binding odds.
  scope :due_for_lock, ->(now = Time.current) {
    where(settled: false).where(kickoff_at: ..(now + VOTE_CLOSES_BEFORE))
  }
  # Candidates for a live-score pull: kicked off within the live window, no
  # final result yet. Lets the live sync skip the API call on quiet days.
  scope :possibly_live, ->(now = Time.current) {
    where(settled: false, result: nil).where(kickoff_at: (now - LIVE_WINDOW)..now)
  }

  # A recorded score/result (but not a settlement flag flip — SettlementJob owns
  # that) refreshes the schedule card and the detail page.
  after_commit :broadcast_result_change, on: :update

  def broadcast_result_change
    return if saved_change_to_settled?
    return unless saved_change_to_result? || saved_change_to_home_score? || saved_change_to_away_score?

    Broadcasts::MatchResultJob.perform_later(id)
  end

  # A schedule import resolved a knockout slot to a real team (home/away team id
  # changed) — push the new matchup to open pages. Result/score updates never
  # touch the team ids, so this won't double-fire with broadcast_result_change.
  after_commit :broadcast_fixture_change, on: :update

  def broadcast_fixture_change
    return unless saved_change_to_home_team_id? || saved_change_to_away_team_id?

    Broadcasts::MatchScheduleJob.perform_later(id)
  end

  class << self
    def knockout?(stage)
      KNOCKOUT_STAGES.include?(stage)
    end

    def allows_draw?(stage)
      !knockout?(stage)
    end

    def stage_label(stage)
      I18n.t("stages.#{stage}", default: stage)
    end

    def pick_label(pick)
      I18n.t("matches.result_label.#{pick}", default: pick)
    end
  end

  def vote_opens_at
    kickoff_day = kickoff_at.in_time_zone(FormatHelper::DISPLAY_TIME_ZONE).to_date
    (kickoff_day - (VOTE_OPENS_DAYS_AHEAD - 1)).in_time_zone(FormatHelper::DISPLAY_TIME_ZONE)
  end

  def vote_closes_at
    kickoff_at - VOTE_CLOSES_BEFORE
  end

  # Both teams are determined (knockout placeholders are not). Drives votability
  # — independent of whether any odds line exists.
  def bettable?
    home_team_id.present? && away_team_id.present?
  end

  # Precise port of the legacy deriveStatus state machine, plus :live in play.
  def status(now: Time.current)
    return :settled if settled?
    return :live if live?(now: now)
    return :locked if now >= vote_closes_at
    return :scheduled if now < vote_opens_at

    bettable? ? :open : :upcoming
  end

  def live?(now: Time.current)
    !settled? && result.blank? && now >= kickoff_at && now < kickoff_at + LIVE_WINDOW
  end

  def votable?(now: Time.current)
    status(now: now) == :open
  end

  def knockout?
    self.class.knockout?(stage)
  end

  def allows_draw?
    !knockout?
  end

  # Goalscorers for this match, earliest first — drives the result panel's goal
  # log on the detail page. Goals come from openfootball (Openfootball::ScheduleImport),
  # independent of the football-data.org score, so the list can lag the score.
  def goal_log
    goals.includes(:team).order(:minute, :id)
  end

  def valid_picks
    allows_draw? ? PICKS : %w[home away]
  end

  # Bottle amounts a player may stake on this match. A single-element list (group)
  # means the stake is fixed and the picker hides the amount selector.
  def stake_options
    STAKE_OPTIONS_BY_STAGE.fetch(stage, [ 1.0 ])
  end

  # Middle option, pre-selected in the picker (and the only value for group).
  def default_stake
    options = stake_options
    options[options.length / 2]
  end

  def valid_stake?(value)
    stake_options.include?(value.to_f)
  end

  # Backward-compatible alias: callers that read match.stake as "this match's
  # stake" now get the default (middle) option.
  def stake
    default_stake
  end

  # Result implied by the score; nil when undecidable (no score, or a knockout
  # draw — where the advancing side must be picked explicitly).
  def derive_result_from_score(home_score, away_score)
    return nil if home_score.nil? || away_score.nil?
    return "home" if home_score > away_score
    return "away" if home_score < away_score

    knockout? ? nil : "draw"
  end

  # Record the score + result without settling (no ledger, settled stays false).
  # Used by the results sync (explicit winner, covering ET/penalties) and admin
  # score edits on un-settled matches (result derived from the score). Each
  # successful record immediately enqueues an auto-settlement for this match;
  # the job no-ops if a settler (or an earlier run) settled it first.
  def record_result!(home_score:, away_score:, result: nil)
    raise DomainError, I18n.t("errors.match.already_settled") if settled?

    resolved = result.presence || derive_result_from_score(home_score, away_score)
    unless resolved
      raise DomainError, I18n.t(knockout? ? "errors.match.knockout_tie" : "errors.match.missing_score")
    end

    update!(result: resolved, home_score: home_score, away_score: away_score, result_at: Time.current)
    AutoSettleJob.schedule(self)
  end

  # Correct or fill a settled match's display score without re-running settlement.
  def update_display_score!(home_score:, away_score:)
    update!(home_score: home_score, away_score: away_score)
  end

  # In-play score refresh: writes the score only, never the result — the result
  # is the "finished" marker that feeds the settle list and auto-settlement, so
  # a live score must not be mistakable for a final one. Returns true when the
  # score changed; no-ops (false) once a result exists or the match settled.
  def record_live_score!(home_score:, away_score:)
    return false if settled? || result.present? || home_score.nil? || away_score.nil?
    return false if self.home_score == home_score && self.away_score == away_score

    update!(home_score: home_score, away_score: away_score)
    true
  end

  def vote_tally
    Vote.tally_for(self)
  end

  # Live crowd odds from the current tally (nil when nothing wagered).
  def current_vote_odds
    VoteOdds.from_tally(vote_tally, allows_draw: allows_draw?)
  end

  # Latest odds per source for display: market (polymarket), crowd snapshot, and
  # the locked market line used for "crowd vs market" comparison.
  def display_odds
    {
      polymarket: latest_snapshot("polymarket"),
      vote: latest_snapshot("vote"),
      locked: locked_market_odds
    }
  end

  # Freeze the binding odds, idempotent per source. Settlement uses the locked
  # crowd-vote odds (the market line is frozen only for display). Returns the
  # locked vote snapshot (the settlement basis) or nil when no one voted.
  def ensure_locked_odds!(now: Time.current)
    unless odds_snapshots.exists?(locked: true, source: OddsSnapshot::MARKET_SOURCES)
      latest = latest_market_odds
      write_locked_snapshot!(latest.source, latest, now) if latest
    end

    vote = locked_vote_odds
    if vote.nil?
      crowd = VoteOdds.from_tally(vote_tally, allows_draw: allows_draw?)
      vote = write_locked_snapshot!("vote", crowd, now) if crowd
    end
    vote
  end

  private

  def latest_snapshot(source)
    odds_snapshots.where(source: source).order(locked: :desc, taken_at: :desc).first
  end

  def latest_market_odds
    odds_snapshots.where(source: OddsSnapshot::MARKET_SOURCES)
      .order(locked: :desc, taken_at: :desc).first
  end

  def locked_market_odds
    odds_snapshots.where(locked: true, source: OddsSnapshot::MARKET_SOURCES)
      .order(taken_at: :desc).first
  end

  def locked_vote_odds
    odds_snapshots.where(locked: true, source: "vote").order(taken_at: :desc).first
  end

  def write_locked_snapshot!(source, odds, now)
    odds_snapshots.create!(
      source: source, locked: true,
      p_home: odds.p_home, p_draw: odds.p_draw, p_away: odds.p_away,
      d_home: odds.d_home, d_draw: odds.d_draw, d_away: odds.d_away,
      taken_at: now
    )
  end
end
