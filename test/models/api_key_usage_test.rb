# frozen_string_literal: true

require 'test_helper'

class ApiKeyUsageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(provider: 'github', uid: '1')
    @api_key, = ApiKey.generate!(@user)
  end

  test 'record! 首次建立一列' do
    ApiKeyUsage.record!(@api_key)

    usage = ApiKeyUsage.sole
    assert_equal @user.id, usage.user_id
    assert_equal @api_key.id, usage.api_key_id
    assert_equal Date.current, usage.used_on
    assert_equal 1, usage.count
  end

  test 'record! 同一天累加,不新增列' do
    3.times { ApiKeyUsage.record!(@api_key) }

    assert_equal 1, ApiKeyUsage.count
    assert_equal 3, ApiKeyUsage.sole.count
  end

  test 'record! 不同日期分開記' do
    ApiKeyUsage.record!(@api_key, Date.current)
    ApiKeyUsage.record!(@api_key, Date.current - 1)

    assert_equal 2, ApiKeyUsage.count
  end

  test 'record! 不同 key 分開記,但 user 相同' do
    other_key, = ApiKey.generate!(@user)
    ApiKeyUsage.record!(@api_key)
    ApiKeyUsage.record!(other_key)

    assert_equal 2, ApiKeyUsage.count
    assert_equal 2, ApiKeyUsage.where(user: @user).sum(:count)
  end
end
