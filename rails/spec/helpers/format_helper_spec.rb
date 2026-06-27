require "rails_helper"

# Expected zh-CN strings were captured from Chromium's ICU (the same engine the
# legacy Next.js app rendered with) so the Ruby port matches byte-for-byte.
RSpec.describe FormatHelper, type: :helper do
  # 2026-06-11 03:00 UTC == 2026-06-11 11:00 Beijing (Thursday)
  let(:thu_morning) { Time.utc(2026, 6, 11, 3, 0) }

  describe "#day_key" do
    it "keys by Beijing calendar day (zero-padded)" do
      expect(helper.day_key(thu_morning)).to eq("2026-06-11")
      expect(helper.day_key(Time.utc(2026, 1, 5, 1, 30))).to eq("2026-01-05")
    end

    it "rolls the day at Beijing midnight, not UTC midnight" do
      # 16:00 UTC is exactly 00:00 the next day in Beijing.
      expect(helper.day_key(Time.utc(2026, 6, 10, 16, 0))).to eq("2026-06-11")
      expect(helper.day_key(Time.utc(2026, 6, 10, 15, 59))).to eq("2026-06-10")
    end
  end

  describe "#format_day_label" do
    it "renders 'M月D日 周X' with unpadded month/day" do
      expect(helper.format_day_label(thu_morning)).to eq("6月11日 周四")
      expect(helper.format_day_label(Time.utc(2026, 1, 5, 1, 30))).to eq("1月5日 周一")
    end
  end

  describe "#format_kickoff" do
    it "renders 'M/D HH:MM 周X'" do
      expect(helper.format_kickoff(thu_morning)).to eq("6/11 11:00 周四")
      expect(helper.format_kickoff(Time.utc(2026, 1, 5, 1, 30))).to eq("1/5 09:30 周一")
    end
  end

  describe "#format_time_only" do
    it "renders zero-padded 24h time" do
      expect(helper.format_time_only(thu_morning)).to eq("11:00")
      expect(helper.format_time_only(Time.utc(2026, 6, 10, 16, 0))).to eq("00:00")
      expect(helper.format_time_only(Time.utc(2026, 6, 10, 15, 59))).to eq("23:59")
    end
  end

  describe "#format_countdown" do
    let(:now) { Time.utc(2026, 6, 11, 3, 0) }

    it "returns '已开赛' once kickoff has passed" do
      expect(helper.format_countdown(now, now)).to eq("已开赛")
      expect(helper.format_countdown(now - 60, now)).to eq("已开赛")
    end

    it "shows days+hours, then hours+minutes, then minutes" do
      expect(helper.format_countdown(now + 86_400 + 3_600, now)).to eq("1天1小时后")
      expect(helper.format_countdown(now + 3_600 + 120, now)).to eq("1小时2分后")
      expect(helper.format_countdown(now + 300, now)).to eq("5分钟后")
      expect(helper.format_countdown(now + 30, now)).to eq("0分钟后")
    end
  end

  describe "#format_bottles" do
    it "prefixes positives with '+', keeps two decimals, and collapses -0.0" do
      expect(helper.format_bottles(2.5)).to eq("+2.50")
      expect(helper.format_bottles(-1.0)).to eq("-1.00")
      expect(helper.format_bottles(0)).to eq("0.00")
      expect(helper.format_bottles(-0.0)).to eq("0.00")
      expect(helper.format_bottles(0.37)).to eq("+0.37")
      expect(helper.format_bottles(3.14159)).to eq("+3.14")
    end
  end

  describe "#format_decimal" do
    it "renders two places; nil and non-finite become an em dash" do
      expect(helper.format_decimal(2.0)).to eq("2.00")
      expect(helper.format_decimal(3.14159)).to eq("3.14")
      expect(helper.format_decimal(nil)).to eq("—")
      expect(helper.format_decimal(1.0 / 0)).to eq("—")
      expect(helper.format_decimal(0.0 / 0)).to eq("—")
    end
  end

  describe "#relative_day_heading" do
    it "labels today/tomorrow/yesterday and nil otherwise" do
      expect(helper.relative_day_heading("2026-06-11", "2026-06-11")).to eq([ "今天", true ])
      expect(helper.relative_day_heading("2026-06-12", "2026-06-11")).to eq([ "明天", false ])
      expect(helper.relative_day_heading("2026-06-10", "2026-06-11")).to eq([ "昨天", false ])
      expect(helper.relative_day_heading("2026-06-13", "2026-06-11")).to eq([ nil, false ])
    end

    it "crosses month and year boundaries" do
      expect(helper.relative_day_heading("2026-07-01", "2026-06-30")).to eq([ "明天", false ])
      expect(helper.relative_day_heading("2026-12-31", "2027-01-01")).to eq([ "昨天", false ])
    end
  end

  describe "#day_key_offset" do
    it "shifts whole days with zero-padding across boundaries" do
      expect(helper.day_key_offset("2026-06-30", 1)).to eq("2026-07-01")
      expect(helper.day_key_offset("2026-01-01", -1)).to eq("2025-12-31")
    end
  end

  describe "localized rendering" do
    let(:now) { Time.utc(2026, 6, 11, 3, 0) }

    it "renders the day label per locale" do
      expect(I18n.with_locale(:"zh-TW") { helper.format_day_label(thu_morning) }).to eq("6月11日 週四")
      expect(I18n.with_locale(:en) { helper.format_day_label(thu_morning) }).to eq("Thu, Jun 11")
      expect(I18n.with_locale(:ja) { helper.format_day_label(thu_morning) }).to eq("6月11日(木)")
    end

    it "renders kickoff per locale" do
      expect(I18n.with_locale(:en) { helper.format_kickoff(thu_morning) }).to eq("Thu 6/11 11:00")
      expect(I18n.with_locale(:ja) { helper.format_kickoff(thu_morning) }).to eq("6/11 11:00(木)")
    end

    it "renders countdown per locale" do
      expect(I18n.with_locale(:en) { helper.format_countdown(now + 86_400 + 3_600, now) }).to eq("1d 1h left")
      expect(I18n.with_locale(:ja) { helper.format_countdown(now + 300, now) }).to eq("5分後")
      expect(I18n.with_locale(:"zh-TW") { helper.format_countdown(now, now) }).to eq("已開賽")
    end

    it "renders relative day headings per locale" do
      expect(I18n.with_locale(:en) { helper.relative_day_heading("2026-06-11", "2026-06-11") }).to eq([ "Today", true ])
      expect(I18n.with_locale(:ja) { helper.relative_day_heading("2026-06-12", "2026-06-11") }).to eq([ "明日", false ])
    end
  end
end
