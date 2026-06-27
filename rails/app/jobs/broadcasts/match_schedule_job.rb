module Broadcasts
  # A knockout slot resolved to a real team (or the matchup otherwise changed)
  # during a schedule import — refresh the schedule card's teams block so the
  # code (e.g. "W74") flips to the real flag + name without a reload, and morph
  # the detail page. Never touches scores/votes; card_meta is left alone so a
  # viewer's per-user "已预测" mark isn't clobbered.
  class MatchScheduleJob < ApplicationJob
    include Renderable
    queue_as :default

    def perform(match_id)
      match = find_match(match_id)
      return unless match

      broadcast_card_teams(match)
      broadcast_refresh_each_locale("match", match)
    end
  end
end
