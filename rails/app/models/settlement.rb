class Settlement < ApplicationRecord
  # Raised (rolling back the transaction) when a commit settles nothing; carries
  # the first skip reason so the controller can show why.
  CommitError = Class.new(StandardError)

  CommitResult = Struct.new(:settlement, :settled, :skipped, keyword_init: true)
  # A bettor's net across one settlement record, for the "结算记录" history.
  Payout = Struct.new(:user, :net, keyword_init: true)

  belongs_to :created_by, class_name: "User", optional: true
  has_many :matches, dependent: :nullify

  validates :match_count, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(id: :desc) }

  # Per-bettor net across this record's matches, read from the ledger so it
  # matches the committed payouts exactly, sorted by net descending.
  def payouts
    @payouts ||= begin
      net_by_user = LedgerEntry.where(match_id: matches.select(:id)).group(:user_id).sum(:delta)
      users_by_id = User.where(id: net_by_user.keys).index_by(&:id)
      net_by_user
        .map { |user_id, net| Payout.new(user: users_by_id[user_id], net: net) }
        .sort_by { |payout| -payout.net }
    end
  end

  # Total bottles changing hands (sum of the winners' positive nets).
  def bottles
    payouts.sum { |payout| [ 0.0, payout.net ].max }
  end

  # Settling fans out to schedule cards, detail pages, leaderboard, each
  # bettor's ledger and the admin (see Broadcasts::SettlementJob).
  after_commit :broadcast_settlement, on: :create

  def broadcast_settlement
    Broadcasts::SettlementJob.perform_later(id)
  end

  class << self
    # Dry-run a batch settlement: compute each person's net buy/receive for the
    # selected matches without writing anything. `included` opts specific voters
    # in per match (see resolve_included for the three-state semantics).
    def preview(match_ids, included: nil)
      preview_matches = []
      skipped = []
      net_by_user = Hash.new(0.0)

      match_ids.each do |match_id|
        match = Match.find_by(id: match_id)
        if (reason = settle_block_reason(match))
          skipped << { match_id: match_id, reason: reason }
          next
        end

        detailed = Vote.detailed_for(match).to_a
        participating = resolve_participants(match_id, included, detailed)
        if participating == :skip
          skipped << { match_id: match_id, reason: I18n.t("errors.settlement.no_participants") }
          next
        end

        PariMutuel.deltas(participating, match.result).each do |delta|
          net_by_user[delta.user_id] += delta.delta
        end
        preview_matches << Preview::Match.new(
          match_id: match.id, result: match.result,
          home_score: match.home_score, away_score: match.away_score,
          voters: detailed.length, votes: roster_votes(detailed)
        )
      end

      Preview.new(
        ok: preview_matches.any?,
        error: preview_matches.any? ? nil : (skipped.first&.fetch(:reason, nil) || I18n.t("errors.settlement.nothing_to_settle")),
        matches: preview_matches,
        skipped: skipped,
        users: preview_users(net_by_user)
      )
    end

    # Commit a batch settlement: one settlement record, each voter's pari-mutuel
    # delta written to the ledger (idempotent via the unique index), and the
    # matches marked settled & linked. Atomic; raises CommitError (rolling back)
    # when nothing settles. Returns a CommitResult on success.
    def commit!(match_ids, settler:, included: nil)
      now = Time.current

      transaction do
        settlement = create!(created_by: settler, match_count: 0)
        skipped = []
        settled = 0

        match_ids.each do |match_id|
          match = Match.find_by(id: match_id)
          if (reason = settle_block_reason(match))
            skipped << { match_id: match_id, reason: reason }
            next
          end

          detailed = Vote.detailed_for(match).to_a
          participating = resolve_participants(match_id, included, detailed)
          if participating == :skip
            skipped << { match_id: match_id, reason: I18n.t("errors.settlement.no_participants") }
            next
          end

          match.ensure_locked_odds!(now: now)
          write_ledger(match, participating, now)
          match.update!(settled: true, settlement: settlement)
          settled += 1
        end

        raise CommitError, (skipped.first&.fetch(:reason, nil) || I18n.t("errors.settlement.nothing_to_settle")) if settled.zero?

        settlement.update!(match_count: settled)
        CommitResult.new(settlement: settlement, settled: settled, skipped: skipped)
      end
    end

    private

    def settle_block_reason(match)
      return I18n.t("errors.settlement.match_missing") if match.nil?
      return I18n.t("errors.settlement.already_settled") if match.settled?
      return I18n.t("errors.settlement.no_result") if match.result.blank?

      nil
    end

    # Resolve the participating voters for one match. A missing `included` key
    # defaults to every real voter; an explicit array intersects with the real
    # voters (so the client can never settle a non-voter); an explicit empty
    # array means "skip this match" — signalled by the :skip sentinel.
    def resolve_participants(match_id, included, detailed)
      raw = included && (included[match_id.to_s] || included[match_id])
      unless raw.is_a?(Array)
        return detailed
      end

      allowed = raw.filter_map { |value| Integer(value, exception: false) }.to_set
      participating = detailed.select { |vote| allowed.include?(vote.user_id) }
      participating.empty? ? :skip : participating
    end

    def write_ledger(match, participating, now)
      rows = PariMutuel.deltas(participating, match.result).map do |delta|
        {
          match_id: match.id, user_id: delta.user_id, pick: delta.pick,
          stake: delta.stake, d_used: delta.d_used, won: delta.won, delta: delta.delta,
          created_at: now, updated_at: now
        }
      end
      LedgerEntry.insert_all(rows, unique_by: [ :match_id, :user_id ]) if rows.any?
    end

    def roster_votes(detailed)
      detailed.map do |vote|
        Preview::RosterVote.new(
          user_id: vote.user_id, nickname: vote.user.nickname,
          emoji: vote.user.emoji, pick: vote.pick, stake: vote.stake
        )
      end
    end

    def preview_users(net_by_user)
      return [] if net_by_user.empty?

      users_by_id = User.where(id: net_by_user.keys).index_by(&:id)
      net_by_user
        .map.with_index do |(user_id, net), index|
          user = users_by_id[user_id]
          [ Preview::User.new(user_id: user_id, nickname: user&.nickname || "?",
                              emoji: user&.emoji, net: net), index ]
        end
        .sort_by { |preview_user, index| [ -preview_user.net, index ] }
        .map(&:first)
    end
  end
end
