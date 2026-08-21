# frozen_string_literal: true

require 'test_helper'

class OriginStatTest < ActiveSupport::TestCase
  test 'record! 首次建立一列' do
    OriginStat.record!('https://cbetaonline.dila.edu.tw')

    stat = OriginStat.sole
    assert_equal 'https://cbetaonline.dila.edu.tw', stat.origin
    assert_equal Date.current, stat.used_on
    assert_equal 1, stat.count
  end

  test 'record! 同一天同一個 origin 累加' do
    3.times { OriginStat.record!('https://a.example.com') }

    assert_equal 1, OriginStat.count
    assert_equal 3, OriginStat.sole.count
  end

  test 'nil origin 記為 (none)' do
    OriginStat.record!(nil)
    assert_equal OriginStat::NONE, OriginStat.sole.origin
  end

  test '空字串也記為 (none)' do
    OriginStat.record!('')
    assert_equal OriginStat::NONE, OriginStat.sole.origin
  end

  test '不同 origin 分開記' do
    OriginStat.record!('https://a.example.com')
    OriginStat.record!('https://b.example.com')
    assert_equal 2, OriginStat.count
  end

  test '不同日期分開記' do
    OriginStat.record!('https://a.example.com', Date.current)
    OriginStat.record!('https://a.example.com', Date.current - 1)
    assert_equal 2, OriginStat.count
  end

  test 'allowlisted? 判讀是否命中白名單' do
    original = Rails.configuration.api_origin_allowlist
    Rails.configuration.api_origin_allowlist = ['https://a.example.com']

    assert OriginStat.new(origin: 'https://a.example.com').allowlisted?
    assert_not OriginStat.new(origin: 'https://b.example.com').allowlisted?
    assert_not OriginStat.new(origin: OriginStat::NONE).allowlisted?
  ensure
    Rails.configuration.api_origin_allowlist = original
  end
end
