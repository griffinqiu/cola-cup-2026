# Redeemable drinks and their credit cost per bottle. Credits are denominated
# in cola (1 credit = 1 cola); pricier drinks cost more per bottle. Single
# source of truth — edit here to change the menu or prices. Display names are
# localized (drinks.* in the locale files), looked up lazily via #name.
Drink = Struct.new(:key, :emoji, :cost)

class Drink
  ALL = [
    new("cola", "🥤", 1.0),
    new("icetea", "🧋", 1.5),
    new("alien", "👽", 1.5),
    new("redbull", "🐂", 2.5)
  ].freeze

  def name
    I18n.t("drinks.#{key}")
  end

  def self.find(key)
    ALL.find { |drink| drink.key == key }
  end
end
