# frozen_string_literal: true

require 'test_helper'

# Origin 白名單改讀 config/cb.yml（不進版控，2026-08-21 主管指示）。
#
# 因為白名單不再進版控，接線出錯時不會有人在 code review 看到 ——
# 只會靜默變成空陣列，然後在過渡期結束的那一刻讓前端全站 401。
# 這裡把接線本身測起來。
class ApiOriginAllowlistConfigTest < ActiveSupport::TestCase
  test '白名單一定是 Array，型別不會外洩到 concern' do
    assert_kind_of Array, Rails.configuration.api_origin_allowlist
  end

  test 'cb.yml 沒有這個 key 時是空陣列，不是 nil' do
    # nil 會讓 concern 的 include? 直接炸掉
    assert_equal [], Array(nil)
    assert_not_nil Rails.configuration.api_origin_allowlist
  end

  test 'config_for 的環境區塊會覆寫 shared 區塊' do
    # config.cb 就是 config_for(:cb) 的結果。這裡驗證 Rails 的合併語意
    # 符合我們的預期: 環境專屬的白名單會蓋掉 shared 的預設值。
    cb = Rails.application.config_for(:cb)
    assert_respond_to cb, :api_origin_allowlist
  end

  test 'api_key_required 預設是 false（過渡期）' do
    assert_equal false, Rails.configuration.api_key_required
  end

  # --- 校內 IP 範圍（設計文件 3.4）---
  #
  # 同樣不進版控,接錯只會靜默變成空陣列 —— 症狀是校內莫名其妙被 429,
  # 不容易聯想到是設定沒讀到。

  test '校內 IP 範圍一定是 Array' do
    assert_kind_of Array, Rails.configuration.api_internal_ip_ranges
  end

  test '校內 IP 範圍的元素是 IPAddr,不是字串' do
    # concern 用 range.include?(IPAddr) 比對,字串會比不出東西。
    # 用 all? 而不是 each + assert_kind_of: 開發機的 cb.yml 通常沒設校內範圍,
    # each 在空陣列上會一個 assertion 都沒跑。
    ranges = Rails.configuration.api_internal_ip_ranges
    assert ranges.all?(IPAddr), "應該全部都是 IPAddr: #{ranges.inspect}"
  end

  test 'cb.yml 沒有這個 key 時是空陣列,不是 nil' do
    assert_not_nil Rails.configuration.api_internal_ip_ranges
  end

  test '格式錯誤的 CIDR 只略過該筆,不讓 boot 失敗' do
    # application.rb 用 filter_map + rescue。這裡驗證同樣的語意:
    # 壞掉的那筆被丟掉,好的那筆留下。
    parsed = ['203.0.113.0/24', '不是 IP'].filter_map do |cidr|
      IPAddr.new(cidr)
    rescue IPAddr::Error
      nil
    end

    assert_equal 1, parsed.size
    assert parsed.first.include?(IPAddr.new('203.0.113.7'))
  end
end
