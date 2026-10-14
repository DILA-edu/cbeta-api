# frozen_string_literal: true

require 'test_helper'
require_relative 'fake_firestore'

class AccountsBackupPruneTest < ActiveSupport::TestCase
  setup do
    @fs = FakeFirestore.new
    travel_to Time.zone.local(2026, 10, 14, 10, 0, 0)
    @keep = User.create!(provider: 'github', uid: '1')
    @gone = User.create!(provider: 'github', uid: '2')
    @gone_key, _ = ApiKey.generate!(@gone)
    @keep_key, _ = ApiKey.generate!(@keep)
    ApiKeyUsage.record!(@gone_key, Date.current - 1)
    ApiKeyUsage.record!(@keep_key, Date.current - 1)
    AccountsBackup::Sync.new(@fs, now: 2.minutes.from_now).call
  end

  def prune(**)
    AccountsBackup::Prune.new(@fs, **).call
  end

  test '刪掉的 user 連同他的 key 與使用紀錄從備份刪除,其他人不受影響' do
    @gone.destroy!

    assert_equal({ 'users' => 1, 'api_keys' => 1, 'api_key_usages' => 1 }, prune)
    assert_equal [ @keep.id.to_s ], @fs.docs['users'].keys
    assert_equal [ @keep_key.id.to_s ], @fs.docs['api_keys'].keys
    assert_equal([ @keep.id ], @fs.docs['api_key_usages'].values.map { |d| d['user_id'] })
  end

  test '沒有刪除時不寫任何東西' do
    writes = @fs.write_count
    assert_equal({}, prune)
    assert_equal writes, @fs.write_count
  end

  test '本機 users 是空的時候中止,不清空備份' do
    ApiKeyUsage.delete_all
    ApiKey.delete_all
    User.delete_all

    assert_raises(AccountsBackup::Error) { prune }
    assert_equal 2, @fs.docs['users'].size
  end

  test '一次要刪的 user 超過上限時中止' do
    @gone.destroy!

    assert_raises(AccountsBackup::Error) { prune(max_users: 0) }
    assert_equal 2, @fs.docs['users'].size
  end

  test '要刪的 user 比本機剩下的多時中止 (user 很少的環境 DB 重建)' do
    travel 5.minutes
    User.create!(provider: 'github', uid: '3')
    AccountsBackup::Sync.new(@fs, now: 2.minutes.from_now).call
    User.where.not(id: @keep.id).destroy_all # 備份 3 個、本機剩 1 個,要刪 2 個

    assert_raises(AccountsBackup::Error) { prune }
    assert_equal 3, @fs.docs['users'].size
  end

  test '明確指定 max_users (MAX_PRUNE) 時以它為準' do
    @gone.destroy! # 備份 2 個、本機剩 1 個,要刪 1 個: 預設可過
    User.where(id: @keep.id).delete_all
    User.create!(provider: 'github', uid: '3')
    travel 5.minutes
    AccountsBackup::Sync.new(@fs, now: 2.minutes.from_now).call # 備份 3 個、本機 1 個

    assert_raises(AccountsBackup::Error) { prune }
    assert_equal({ 'users' => 2 }, prune(max_users: 2).slice('users'))
  end

  test 'run! 先推變更再刪除,回傳有異動的表' do
    @gone.destroy!
    travel 5.minutes
    @keep_key.revoke!
    travel 5.minutes

    result = AccountsBackup.run!(@fs)

    assert_equal 1, result['api_keys synced']
    assert_equal 1, result['users pruned']
    assert_not_nil @fs.docs['api_keys'][@keep_key.id.to_s]['revoked_at']
  end
end
