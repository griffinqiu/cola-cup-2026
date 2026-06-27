# Maps raw language inputs to one of the app's supported locales, without
# pulling in the http_accept_language gem. The controller decides the priority
# order (param > user > cookie > header); this PORO only knows how to turn an
# Accept-Language header into a supported locale, returning nil when nothing
# matches so the caller can fall back to the default.
class LocaleResolver
  # Best supported locale from an Accept-Language header, honoring q-weights
  # ("ja,zh-TW;q=0.9,en;q=0.5"). Returns nil when no tag maps to a locale.
  def self.from_header(header)
    return nil if header.blank?

    parse(header).each do |tag|
      locale = normalize(tag)
      return locale if locale
    end
    nil
  end

  # Reduce a single BCP-47 tag to a supported locale. Traditional Chinese
  # variants (Hant / TW / HK / MO) resolve to zh-TW; every other Chinese tag
  # falls to the Simplified default.
  def self.normalize(tag)
    return nil if tag.blank?

    primary, region = tag.to_s.strip.downcase.split(/[-_]/, 2)
    case primary
    when "zh" then traditional?(region) ? "zh-TW" : "zh-CN"
    when "ja" then "ja"
    when "en" then "en"
    end
  end

  def self.traditional?(region)
    return false if region.blank?

    %w[hant tw hk mo].any? { |variant| region.start_with?(variant) }
  end

  # Tags from an Accept-Language header, highest q-weight first; q=0 dropped.
  def self.parse(header)
    header.to_s.split(",").filter_map { |part| weighted_tag(part) }
      .sort_by { |(_tag, q)| -q }
      .map(&:first)
  end

  def self.weighted_tag(part)
    tag, *params = part.split(";").map(&:strip)
    return if tag.blank? || tag == "*"

    q = 1.0
    params.each do |param|
      key, value = param.split("=", 2)
      q = value.to_f if key&.strip == "q"
    end
    return if q <= 0

    [ tag, q ]
  end
end
