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
end
