# frozen_string_literal: true

require 'test_helper'
require_relative 'fake_firestore'

class AccountsBackupSyncTest < ActiveSupport::TestCase
  setup do
    @fs = FakeFirestore.new
    travel_to Time.zone.local(2026, 10, 14, 10, 0, 0)
    @user = User.create!(provider: 'github', uid: '1', email: 'a@example.com', name: 'A')
    @key, _token = ApiKey.generate!(@user)
  end

  def sync(at = Time.current)
    AccountsBackup::Sync.new(@fs, now: at).call
  end

  test '第一次 sync 推出全部 users 與 api_keys,並寫入 meta' do
    result = sync(2.minutes.from_now)

    assert_equal({ 'users' => 1, 'api_keys' => 1, 'api_key_usages' => 0 }, result.counts)
    user_doc = @fs.docs['users'][@user.id.to_s]
    assert_equal 'a@example.com', user_doc['email']
    assert_equal false, user_doc['admin']
    assert_equal @key.token_digest, @fs.docs['api_keys'][@key.id.to_s]['token_digest']
    assert_equal 'test', @fs.docs['meta']['sync']['rails_env']
  end

  test '沒有變更時不寫任何東西' do
    sync(2.minutes.from_now)
    writes = @fs.write_count

    result = sync(10.minutes.from_now)

    assert_equal 0, result.total
    assert_equal writes, @fs.write_count
  end

  test '剛更新、還在 SETTLE_TIME 內的列這輪不推,下一輪才推' do
    result = sync(30.seconds.from_now)
    assert_equal 0, result.total

    result = sync(2.minutes.from_now)
    assert_equal 1, result.counts['users']
  end

  test '只推有變更的列' do
    other = User.create!(provider: 'google_oauth2', uid: '2')
    sync(2.minutes.from_now)

    travel 5.minutes
    @key.revoke!
    result = sync(2.minutes.from_now)

    assert_equal({ 'users' => 0, 'api_keys' => 1, 'api_key_usages' => 0 }, result.counts)
    assert_not_nil @fs.docs['api_keys'][@key.id.to_s]['revoked_at']
    assert @fs.docs['users'].key?(other.id.to_s)
  end

  test 'last_used_at 的更新不會觸發寫入,也不在備份欄位中' do
    sync(2.minutes.from_now)
    travel 5.minutes
    @key.touch_last_used!

    assert_equal 0, sync(2.minutes.from_now).total
    assert_not @fs.docs['api_keys'][@key.id.to_s].key?('last_used_at')
  end

  test 'api_key_usages 只推已結束的日子,且每列只推一次' do
    ApiKeyUsage.record!(@key, Date.current - 1)
    ApiKeyUsage.record!(@key, Date.current)

    result = sync(2.minutes.from_now)
    assert_equal 1, result.counts['api_key_usages']
    assert_equal (Date.current - 1).iso8601, @fs.docs['meta']['sync']['usage_through']

    travel 1.day
    result = sync(2.minutes.from_now)
    assert_equal 1, result.counts['api_key_usages']
    assert_equal [ (Date.current - 2).iso8601, (Date.current - 1).iso8601 ],
                 @fs.docs['api_key_usages'].values.map { |d| d['used_on'] }.sort

    assert_equal 0, sync(3.minutes.from_now).total
  end

  test 'full: true 忽略 watermark 整份重推 (從 pg_dump 還原後補回被刪的文件)' do
    sync(2.minutes.from_now)
    @fs.docs['users'].clear

    assert_equal 0, sync(5.minutes.from_now).total
    result = AccountsBackup::Sync.new(@fs, now: 5.minutes.from_now, full: true).call
    assert_equal 1, result.counts['users']
    assert @fs.docs['users'].key?(@user.id.to_s)
  end

  test 'Firestore DB 屬於其他環境時中止' do
    @fs.upsert_all([ [ 'meta', 'sync', { 'rails_env' => 'production' } ] ])

    error = assert_raises(AccountsBackup::Error) { sync(2.minutes.from_now) }
    assert_match 'production', error.message
  end

  test 'accounts DB 被重建 (同 id 但 created_at 不同) 時中止,不覆寫備份' do
    sync(2.minutes.from_now)

    # 模擬重建: 清空後新使用者拿到同一個 id
    old_id = @user.id
    ApiKey.delete_all
    User.delete_all
    travel 1.hour
    User.create!(id: old_id, provider: 'github', uid: '999')

    assert_raises(AccountsBackup::Error) { sync(2.minutes.from_now) }
    assert_equal '1', @fs.docs['users'][old_id.to_s]['uid']
  end

  test '合法刪掉最大 id 或哨兵列之後,sync 照常繼續' do
    sync(2.minutes.from_now)
    @user.destroy! # 唯一的 user 與 key,同時是最大 id 與哨兵

    travel 5.minutes
    User.create!(provider: 'github', uid: '2')
    assert_equal 1, sync(2.minutes.from_now).counts['users']
  end

  test '本機刪掉的列不會從備份刪除' do
    sync(2.minutes.from_now)
    @user.destroy!

    sync(5.minutes.from_now)
    assert @fs.docs['users'].key?(@user.id.to_s)
  end
end
