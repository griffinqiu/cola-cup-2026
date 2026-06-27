class LocalesController < ApplicationController
  # Persist the language switch. Anonymous visitors keep it in a permanent
  # cookie; signed-in users also store it on their account so it follows them
  # across devices. update_column avoids bumping users.updated_at, which would
  # needlessly churn the leaderboard cache signature.
  def update
    locale = params[:locale].to_s
    if User::LOCALES.include?(locale)
      cookies.permanent[:locale] = { value: locale, same_site: :lax, httponly: true }
      current_user.update_column(:locale, locale) if user_signed_in?
    end
    redirect_back fallback_location: root_path, status: :see_other
  end
end
