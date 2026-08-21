# frozen_string_literal: true

require 'test_helper'

# 過渡期埋點是不是真的有在記（設計文件 4.5）。
class OriginStatsTest < ActionDispatch::IntegrationTest
  ENDPOINT = '/changes'

  test '帶 Origin 的 request 有記下來' do
    get ENDPOINT, headers: { 'Origin' => 'https://cbetaonline.dila.edu.tw' }

    stat = OriginStat.find_by(origin: 'https://cbetaonline.dila.edu.tw',
                              used_on: Date.current)
    assert_equal 1, stat.count
  end

  test '沒帶 Origin 的 request 記為 (none)' do
    get ENDPOINT

    stat = OriginStat.find_by(origin: OriginStat::NONE, used_on: Date.current)
    assert_equal 1, stat.count
  end

  test '多次呼叫累加' do
    3.times { get ENDPOINT, headers: { 'Origin' => 'https://a.example.com' } }

    assert_equal 3, OriginStat.find_by(origin: 'https://a.example.com').count
  end

  test '埋點失敗不影響 API 回應' do
    OriginStat.singleton_class.alias_method(:record_original!, :record!)
    OriginStat.define_singleton_method(:record!) { |*| raise 'boom' }

    get ENDPOINT
    assert_response :success
  ensure
    OriginStat.singleton_class.alias_method(:record!, :record_original!)
    OriginStat.singleton_class.remove_method(:record_original!)
  end
end
