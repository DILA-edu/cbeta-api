# frozen_string_literal: true

require 'test_helper'

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(provider: 'github', uid: '1', email: 'a@example.com')
  end

  test 'generate! 回傳明文,格式為 cbeta_ 前綴' do
    _api_key, token = ApiKey.generate!(@user)
    assert token.start_with?(ApiKey::TOKEN_PREFIX)
  end

  test '只存 digest,不存明文' do
    api_key, token = ApiKey.generate!(@user)
    assert_equal Digest::SHA256.hexdigest(token), api_key.token_digest
    assert_not_equal token, api_key.token_digest
    assert_not ApiKey.column_names.include?('token')
  end

  test 'token_hint 只存前綴' do
    api_key, token = ApiKey.generate!(@user)
    expected_length = ApiKey::TOKEN_PREFIX.length + ApiKey::HINT_LENGTH
    assert_equal expected_length, api_key.token_hint.length
    assert token.start_with?(api_key.token_hint)
  end

  test '每次產生的 token 都不同' do
    tokens = 2.times.map { ApiKey.generate!(@user).last }
    assert_equal 2, tokens.uniq.size
  end

  test 'authenticate 用明文找到 key' do
    api_key, token = ApiKey.generate!(@user)
    assert_equal api_key, ApiKey.authenticate(token)
  end

  test 'authenticate 對無效的 token 回 nil' do
    ApiKey.generate!(@user)
    assert_nil ApiKey.authenticate('cbeta_not-a-real-token')
  end

  test 'authenticate 對 blank 回 nil' do
    assert_nil ApiKey.authenticate(nil)
    assert_nil ApiKey.authenticate('')
  end

  test '撤銷後 authenticate 立刻回 nil' do
    api_key, token = ApiKey.generate!(@user)
    api_key.revoke!
    assert_nil ApiKey.authenticate(token)
  end

  test 'revoke! 是軟刪除,保留稽核紀錄' do
    api_key, = ApiKey.generate!(@user)
    api_key.revoke!
    assert_not api_key.active?
    assert api_key.persisted?
    assert_not_nil api_key.reload.revoked_at
  end

  test 'revoke! 對已撤銷的 key 回 false' do
    api_key, = ApiKey.generate!(@user)
    api_key.revoke!
    assert_not api_key.revoke!
  end

  test '超過有效 key 上限就不能再建' do
    User::MAX_ACTIVE_API_KEYS.times { ApiKey.generate!(@user) }
    assert_raises(ActiveRecord::RecordInvalid) { ApiKey.generate!(@user) }
  end

  test '已撤銷的 key 不計入上限' do
    keys = User::MAX_ACTIVE_API_KEYS.times.map { ApiKey.generate!(@user).first }
    keys.first.revoke!
    assert_nothing_raised { ApiKey.generate!(@user) }
  end

  test '上限是 per-user' do
    other = User.create!(provider: 'github', uid: '2')
    User::MAX_ACTIVE_API_KEYS.times { ApiKey.generate!(@user) }
    assert_nothing_raised { ApiKey.generate!(other) }
  end

  test 'active scope 只含未撤銷的' do
    keys = 2.times.map { ApiKey.generate!(@user).first }
    keys.first.revoke!
    assert_equal [keys.last], ApiKey.active.to_a
  end

  test 'touch_last_used! 首次會寫入' do
    api_key, = ApiKey.generate!(@user)
    now = Time.current
    api_key.touch_last_used!(now)
    assert_in_delta now.to_i, api_key.reload.last_used_at.to_i, 1
  end

  test 'touch_last_used! 在節流時間內不寫入' do
    api_key, = ApiKey.generate!(@user)
    first = 10.minutes.ago
    api_key.update_column(:last_used_at, first)

    api_key.touch_last_used!(Time.current)
    assert_in_delta first.to_i, api_key.reload.last_used_at.to_i, 1
  end

  test 'touch_last_used! 超過節流時間才寫入' do
    api_key, = ApiKey.generate!(@user)
    api_key.update_column(:last_used_at, (ApiKey::LAST_USED_THROTTLE + 1.minute).ago)

    now = Time.current
    api_key.touch_last_used!(now)
    assert_in_delta now.to_i, api_key.reload.last_used_at.to_i, 1
  end
end
