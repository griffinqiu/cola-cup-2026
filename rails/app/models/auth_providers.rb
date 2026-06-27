# Single source of truth for which login providers are enabled and how they are
# labelled. Read at call-time (not boot) so callers reflect the current ENV.
# Presence of the provider's key env var is the on/off switch.
module AuthProviders
  module_function

  def twitter_enabled?
    ENV["AUTH_TWITTER_ID"].present?
  end

  def oidc_enabled?
    ENV["OIDC_ISSUER"].present?
  end

  def oidc_display_name
    # ENV values arrive tagged with the process's external encoding, which can be
    # ASCII-8BIT when the host lacks a UTF-8 LANG; re-tag so a non-ASCII display
    # name compares/renders as UTF-8.
    override = ENV["OIDC_DISPLAY_NAME"].presence&.dup&.force_encoding(Encoding::UTF_8)
    override || I18n.t("auth.oidc_default_name")
  end

  def any_enabled?
    twitter_enabled? || oidc_enabled?
  end
end
