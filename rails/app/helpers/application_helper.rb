module ApplicationHelper
  # Devise exposes `current_user` as a view helper once auth lands (阶段4).
  # Until then it is undefined, so guard against NameError and treat as anonymous.
  def signed_in_user
    current_user if respond_to?(:current_user)
  end

  # The schedule tab is the umbrella for the whole match-browsing flow, so it also
  # lights up on match, standings, scorer, third-place and team pages reached from
  # it. "/me" stays an exact match so the redeem tab doesn't also light up on the
  # settings page (/me/settings), which owns its own tab; every other tab matches
  # on path prefix.
  def nav_tab_active?(href)
    path = request.path
    case href
    when "/"
      path == "/" || path.start_with?("/matches", "/groups", "/scorers", "/third-place", "/teams")
    when "/me"
      path == "/me"
    else
      path.start_with?(href)
    end
  end
end
