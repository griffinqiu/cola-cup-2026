require "rails_helper"

RSpec.describe LocaleResolver do
  describe ".normalize" do
    it "maps simplified Chinese tags to zh-CN" do
      expect(described_class.normalize("zh")).to eq("zh-CN")
      expect(described_class.normalize("zh-CN")).to eq("zh-CN")
      expect(described_class.normalize("zh-Hans")).to eq("zh-CN")
    end

    it "maps traditional Chinese variants to zh-TW" do
      expect(described_class.normalize("zh-TW")).to eq("zh-TW")
      expect(described_class.normalize("zh-Hant")).to eq("zh-TW")
      expect(described_class.normalize("zh-HK")).to eq("zh-TW")
      expect(described_class.normalize("zh-Hant-TW")).to eq("zh-TW")
    end

    it "maps Japanese and English regional tags" do
      expect(described_class.normalize("ja")).to eq("ja")
      expect(described_class.normalize("ja-JP")).to eq("ja")
      expect(described_class.normalize("en-US")).to eq("en")
    end

    it "returns nil for unsupported or blank tags" do
      expect(described_class.normalize("fr")).to be_nil
      expect(described_class.normalize("")).to be_nil
      expect(described_class.normalize(nil)).to be_nil
    end
  end

  describe ".from_header" do
    it "picks the highest q-weighted supported tag" do
      expect(described_class.from_header("ja,zh-TW;q=0.9,en;q=0.5")).to eq("ja")
      expect(described_class.from_header("fr;q=1.0,en;q=0.8,ja;q=0.7")).to eq("en")
    end

    it "skips q=0 tags and unsupported languages" do
      expect(described_class.from_header("de;q=0,ko,zh-TW;q=0.4")).to eq("zh-TW")
    end

    it "returns nil when nothing matches" do
      expect(described_class.from_header("fr,de,ko")).to be_nil
      expect(described_class.from_header("")).to be_nil
      expect(described_class.from_header(nil)).to be_nil
    end
  end
end
