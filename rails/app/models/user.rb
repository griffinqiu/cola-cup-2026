class User < ApplicationRecord
  # database_authenticatable is only the Warden base — there is no password entry
  # (sessions/registrations/passwords routes are skipped); login is via OmniAuth
  # providers (Twitter/X and/or OIDC).
  devise :database_authenticatable, :rememberable, :omniauthable,
    omniauth_providers: [ :twitter2, :openid_connect ]

  MAX_NICKNAME = 16
  FALLBACK_NICKNAME = "球迷"

  # Supported UI locales, in display order. Single source of truth for the
  # locale validation, the Accept-Language resolver fallback set, and the
  # language switcher. LOCALE_NAMES holds each locale's endonym for the picker.
  LOCALES = %w[zh-CN zh-TW en ja].freeze
  LOCALE_NAMES = {
    "zh-CN" => "简体中文",
    "zh-TW" => "繁體中文",
    "en" => "English",
    "ja" => "日本語"
  }.freeze
  # Maps the OmniAuth strategy name to the provider value stored on Account.
  # "twitter2" is normalised to "twitter" so legacy data / SETTLER_USERNAMES
  # matching stay unchanged.
  PROVIDERS = { "twitter2" => "twitter", "openid_connect" => "oidc" }.freeze

  LEADERBOARD_CACHE_KEY = "leaderboard/v1".freeze

  # Score tuning for the accuracy boards. Both algorithms are sample-size aware so
  # a lucky 3/3 never outranks a proven 17/20.
  #   神预榜  Bayesian shrinkage: (wins + C·m) / (bets + C), m = global mean hit rate
  #   毒奶榜  Wilson lower bound of the loss rate at 95% confidence (z = 1.96)
  BAYESIAN_PRIOR_BETS = 5
  WILSON_Z = 1.96

  # One cached leaderboard row. Holds only primitives so it Marshals cleanly into
  # Solid Cache — caching the AR rows would drag along attribute/type metadata and
  # the virtual select columns. Exposes exactly the readers leaderboards/_board
  # uses; to_param keeps user_path(entry) generating /users/:id.
  Entry = Data.define(:id, :avatar_url, :emoji, :nickname, :total, :redeemed, :bets, :wins) do
    def to_param = id.to_s
  end

  # A leaderboard variant. Every board re-ranks the same cached Entry list
  # (User.leaderboard) in memory — no extra queries. `metric` tells the row
  # template which value to headline; the ranking itself lives in leaderboard_for.
  # `explainer` (+ optional `formula`) is the public, plain-language description of
  # how the board is computed, shown beneath the table on the leaderboard page.
  # The first board is the default (rendered at /leaderboard and broadcast live).
  Board = Data.define(:key, :name, :emoji, :subtitle, :metric, :explainer, :formula)

  BOARDS = [
    Board.new(
      key: "reaper", name: "镰刀榜", emoji: "🔪", metric: :total,
      subtitle: "可乐净分最高 · 收割之王（兑换不影响排名）",
      explainer: "按可乐净分（赢的瓶数减去输的瓶数）从高到低排名。兑换饮料只是花掉额度，不影响排名。",
      formula: nil
    ),
    Board.new(
      key: "leek", name: "韭菜榜", emoji: "🌱", metric: :total,
      subtitle: "可乐净分最低 · 被割得最惨",
      explainer: "镰刀榜的反面：按可乐净分从低到高排，输得最惨的排最前。只统计参与过预测的人。",
      formula: nil
    ),
    Board.new(
      key: "oracle", name: "神预榜", emoji: "🔮", metric: :hit_rate,
      subtitle: "命中率最高 · 贝叶斯加权，场数越多越稳",
      explainer: "按预测命中率排名，但做了「场数」修正：光靠手气猜中几场不够，要又准又多才稳。" \
                 "只猜 1 场全中不会直接霸榜，会先按全场平均命中率打个折；预测场数越多，你的真实水平占比越高。",
      formula: "贝叶斯加权 =（命中数 + 5 × 全场平均命中率）÷（预测场数 + 5），公开算法，同 IMDB Top 250 加权评分。"
    ),
    Board.new(
      key: "jinx", name: "毒奶榜", emoji: "🥛", metric: :miss_rate,
      subtitle: "押谁谁输 · 最稳定押错的人",
      explainer: "神预榜的反面：按「押错率」排名，同样做了场数修正。偶尔押错一两次不算毒奶，" \
                 "要稳定地押谁谁输、且场数够多，才能名列前茅。",
      formula: "Wilson 置信区间下界（押错率，z = 1.96），公开算法，同 Reddit 评论排序。"
    ),
    Board.new(
      key: "otaku", name: "肥宅榜", emoji: "🥤", metric: :redeemed,
      subtitle: "可乐兑换最多 · 肥宅快乐",
      explainer: "按累计兑换的额度从高到低排名，喝得最多的肥宅排最前。只统计兑换过饮料的人。",
      formula: nil
    )
  ].freeze

  BOARDS_BY_KEY = BOARDS.index_by(&:key).freeze
  DEFAULT_BOARD = BOARDS.first

  has_many :accounts, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :ledger_entries, dependent: :destroy
  has_many :redemptions, dependent: :destroy

  validates :nickname, presence: true, length: { maximum: MAX_NICKNAME }
  validates :locale, inclusion: { in: LOCALES }

  scope :active, -> { where(deleted_at: nil) }

  # Soft delete/restore changes who appears across the app; a nickname/emoji edit
  # only updates display. Avatar refreshes on login are intentionally not broadcast.
  after_commit :broadcast_user_change, on: :update

  def broadcast_user_change
    if saved_change_to_deleted_at?
      Broadcasts::UserVisibilityJob.perform_later(id)
    elsif saved_change_to_nickname? || saved_change_to_emoji?
      Broadcasts::ProfileJob.perform_later(id)
    end
  end

  # Leaderboard ranked by total score (Σ delta) — pure betting performance,
  # redemptions reported alongside but never lower the rank. Returns Entry rows
  # carrying total / redeemed / bets / wins; soft-deleted users are excluded.
  #
  # Cached in Solid Cache under a key stamped with leaderboard_signature, so the
  # cache self-invalidates whenever any input changes — no per-model hooks, which
  # matters because settlements write ledger rows via LedgerEntry.insert_all and
  # bypass callbacks. Both the leaderboard page and the broadcast job
  # (Broadcasts::Renderable#broadcast_leaderboard) call this and share the result.
  def self.leaderboard
    Rails.cache.fetch("#{LEADERBOARD_CACHE_KEY}/#{leaderboard_signature}", expires_in: 12.hours) do
      leaderboard_relation.map do |row|
        Entry.new(
          id: row.id, avatar_url: row.avatar_url, emoji: row.emoji, nickname: row.nickname,
          total: row.total.to_f, redeemed: row.redeemed.to_f, bets: row.bets.to_i, wins: row.wins.to_i
        )
      end
    end
  end

  def self.leaderboard_relation
    active
      .select(
        "users.id, users.avatar_url, users.emoji, users.nickname, users.created_at",
        "COALESCE((SELECT SUM(delta) FROM ledger_entries WHERE user_id = users.id), 0) AS total",
        "COALESCE((SELECT SUM(cost) FROM redemptions WHERE user_id = users.id), 0) AS redeemed",
        "(SELECT COUNT(*) FROM ledger_entries WHERE user_id = users.id) AS bets",
        "COALESCE((SELECT SUM(won) FROM ledger_entries WHERE user_id = users.id), 0) AS wins"
      )
      .order(Arel.sql("total DESC, bets DESC, users.created_at ASC"))
  end

  # Cheap signature that advances whenever a leaderboard input changes: ledger
  # inserts (incl. settlement's insert_all) and redemptions bump a max(:id);
  # nickname/emoji edits and soft delete/restore bump users.updated_at. Far
  # cheaper than the per-user correlated subqueries it guards.
  def self.leaderboard_signature
    [
      LedgerEntry.maximum(:id),
      Redemption.maximum(:id),
      User.maximum(:updated_at).to_f,
      User.active.count
    ].join("-")
  end

  # Resolve a board key from the URL, falling back to the default (镰刀榜) for a
  # missing or unknown key.
  def self.board_for(key)
    BOARDS_BY_KEY.fetch(key.to_s) { DEFAULT_BOARD }
  end

  # Rank the shared, cached leaderboard for one board. The default board reuses
  # the relation's SQL order (total DESC); every other board re-sorts the same
  # Entry array in memory. Accuracy boards exclude users who never bet, then sort
  # by a sample-size-aware score; ties break by more bets, then earliest id.
  def self.leaderboard_for(board)
    rows = leaderboard
    case board.key
    when "leek"
      rows.select { |row| row.bets.positive? }.sort_by { |row| [ row.total, row.id ] }
    when "oracle"
      ranked = rows.select { |row| row.bets.positive? }
      mean = mean_hit_rate(ranked)
      ranked.sort_by { |row| [ -bayesian_hit_score(row.wins, row.bets, mean), -row.bets, row.id ] }
    when "jinx"
      rows.select { |row| row.bets.positive? }
          .sort_by { |row| [ -wilson_lower_bound(row.bets - row.wins, row.bets), -row.bets, row.id ] }
    when "otaku"
      rows.select { |row| row.redeemed.positive? }.sort_by { |row| [ -row.redeemed, row.id ] }
    else
      rows
    end
  end

  def self.mean_hit_rate(rows)
    bets = rows.sum(&:bets)
    bets.positive? ? rows.sum(&:wins).fdiv(bets) : 0.0
  end

  # Posterior mean of the hit rate under a Beta prior worth BAYESIAN_PRIOR_BETS
  # pseudo-bets centred on the global mean — small samples shrink toward the mean.
  def self.bayesian_hit_score(wins, bets, mean)
    (wins + BAYESIAN_PRIOR_BETS * mean) / (bets + BAYESIAN_PRIOR_BETS)
  end

  # Lower bound of the Wilson score interval for a proportion — the standard way
  # to rank a positive rate while penalising small samples.
  def self.wilson_lower_bound(positives, n)
    return 0.0 if n.zero?

    phat = positives.fdiv(n)
    (phat + WILSON_Z**2 / (2 * n) -
      WILSON_Z * Math.sqrt((phat * (1 - phat) + WILSON_Z**2 / (4 * n)) / n)) / (1 + WILSON_Z**2 / n)
  end

  # Link an OAuth identity to a user, creating the user on first login. The
  # provider handle and avatar refresh on every login; the user's edited nickname
  # and emoji are never overwritten. Ports the legacy upsertOAuthUser.
  def self.from_omniauth(auth)
    provider = PROVIDERS.fetch(auth.provider.to_s)
    provider_account_id = auth.uid.to_s
    username = auth.info.nickname.presence
    avatar_url = avatar_for(auth.provider.to_s, auth.info.image)

    account = Account.find_by(provider: provider, provider_account_id: provider_account_id)
    if account
      account.update!(username: username, avatar_url: avatar_url)
      account.user.update!(avatar_url: avatar_url) # nickname / emoji untouched
      return account.user
    end

    transaction do
      user = create!(nickname: nickname_from(auth.info.name), avatar_url: avatar_url)
      user.accounts.create!(
        provider: provider, provider_account_id: provider_account_id,
        username: username, avatar_url: avatar_url
      )
      user
    end
  end

  # Twitter serves a 48px "_normal" avatar; request the 400px variant. Other
  # providers (e.g. the OIDC `picture` claim) are used as-is.
  def self.avatar_for(omniauth_provider, image)
    url = image.presence
    omniauth_provider == "twitter2" ? url&.sub("_normal", "_400x400") : url
  end

  def self.nickname_from(name)
    (name.presence || FALLBACK_NICKNAME).to_s[0, MAX_NICKNAME]
  end

  # Available balance = settled net (Σ ledger delta) − credits spent on drinks.
  def net_balance
    ledger_entries.sum(:delta) - redemptions.sum(:cost)
  end

  def soft_delete!
    update!(deleted_at: Time.current) if deleted_at.nil?
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  def settler?
    Settler.settler?(self)
  end

  # Display handle for the admin roster — the earliest linked account's username.
  def primary_handle
    accounts.min_by(&:created_at)&.username
  end

  # Soft-deleted users cannot sign in (Devise checks this on every authentication).
  def active_for_authentication?
    super && !deleted?
  end

  def inactive_message
    deleted? ? :deleted_account : super
  end
end
