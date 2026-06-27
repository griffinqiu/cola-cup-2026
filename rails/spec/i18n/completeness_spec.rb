require "rails_helper"
require "yaml"
require "set"

# Guards that every supported locale defines exactly the same set of app
# translation keys, so a string is never missing (or stale/extra) in one
# language. zh-CN is the authored source of truth.
RSpec.describe "i18n locale completeness" do
  def deep_merge(a, b)
    a.merge(b) { |_k, va, vb| va.is_a?(Hash) && vb.is_a?(Hash) ? deep_merge(va, vb) : vb }
  end

  def leaf_keys(hash, prefix = "")
    hash.flat_map do |key, value|
      value.is_a?(Hash) ? leaf_keys(value, "#{prefix}#{key}.") : [ "#{prefix}#{key}" ]
    end
  end

  # The authored app locale files per locale (zh-CN is split across the base file
  # and the per-area view files).
  def files_for(locale)
    case locale
    when "zh-CN" then [ "zh-CN.yml", *Dir[Rails.root.join("config/locales/views_*.zh-CN.yml")].map { |p| File.basename(p) } ]
    else [ "#{locale}.yml" ]
    end
  end

  def keys_for(locale)
    files_for(locale).reduce({}) do |acc, name|
      tree = YAML.load_file(Rails.root.join("config/locales", name))[locale] || {}
      deep_merge(acc, tree)
    end.then { |merged| leaf_keys(merged).to_set }
  end

  let(:base_keys) { keys_for("zh-CN") }

  it "configures all four locales as available" do
    expect(I18n.available_locales.map(&:to_s)).to include(*User::LOCALES)
  end

  (User::LOCALES - [ "zh-CN" ]).each do |locale|
    it "#{locale} defines exactly the same keys as zh-CN" do
      keys = keys_for(locale)
      missing = (base_keys - keys).to_a.sort
      extra = (keys - base_keys).to_a.sort
      expect(missing).to be_empty, "#{locale} is MISSING #{missing.size} keys: #{missing.join(', ')}"
      expect(extra).to be_empty, "#{locale} has #{extra.size} EXTRA keys: #{extra.join(', ')}"
    end
  end

  it "covers the same teams in every team-name file" do
    tw = YAML.load_file(Rails.root.join("config/locales/teams.zh-TW.yml")).dig("zh-TW", "teams").keys.to_set
    ja = YAML.load_file(Rails.root.join("config/locales/teams.ja.yml")).dig("ja", "teams").keys.to_set
    expect(tw).to eq(ja)
  end
end
