class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  PER_PAGE = 20

  around_action :switch_locale

  helper_method :current_settler?

  private

  # Resolve and apply the UI locale for the duration of the request. Priority:
  # explicit ?locale= → signed-in user's saved choice → cookie → browser
  # Accept-Language → app default. with_locale restores the previous locale
  # afterwards so background threads are unaffected.
  def switch_locale(&action)
    I18n.with_locale(resolve_locale, &action)
  end

  def resolve_locale
    locale = params[:locale].presence_in(User::LOCALES) ||
      current_user&.locale&.presence_in(User::LOCALES) ||
      cookies[:locale].presence_in(User::LOCALES) ||
      LocaleResolver.from_header(request.headers["Accept-Language"]) ||
      I18n.default_locale
    locale.to_sym
  end

  # Offset/limit pagination for infinite scroll. Fetches one extra row to detect
  # a next page without a separate COUNT. Returns [rows, next_page, offset].
  def paginate_relation(relation)
    page = [ params[:page].to_i, 1 ].max
    offset = (page - 1) * PER_PAGE
    rows = relation.offset(offset).limit(PER_PAGE + 1).to_a
    [ rows.first(PER_PAGE), (page + 1 if rows.size > PER_PAGE), offset ]
  end

  # Gate for self-service actions (vote / redeem / profile): anonymous visitors
  # are sent to the identity prompt instead of a login wall.
  def require_login!
    redirect_to identity_path, status: :see_other unless user_signed_in?
  end

  # Gate for the settlement admin: non-settlers get 403 in place.
  def require_settler!
    return redirect_to(identity_path, status: :see_other) unless user_signed_in?

    head :forbidden unless current_user.settler?
  end

  def current_settler?
    user_signed_in? && current_user.settler?
  end
end
