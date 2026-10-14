# frozen_string_literal: true

require 'test_helper'
require_relative 'fake_firestore'

class AccountsBackupRestoreTest < ActiveSupport::TestCase
  setup do
    @fs = FakeFirestore.new
    travel_to Time.zone.local(2026, 10, 14, 10, 0, 0)
  end

  # 建資料 → sync → 清空本機,模擬 accounts DB 遺失
  def backup_and_wipe
    user = User.create!(provider: 'github', uid: '1', email: 'a@example.com', admin: true)
    revoked, _ = ApiKey.generate!(user)
    revoked.revoke!
    ApiKey.generate!(user)
    ApiKey.generate!(user) # 有效 2 把 + 撤銷 1 把,超過 create 時的上限檢查範圍
    ApiKeyUsage.record!(revoked, Date.current - 1)
    AccountsBackup::Sync.new(@fs, now: 2.minutes.from_now).call

    snapshot = {
      users: User.order(:id).map(&:attributes),
      api_keys: ApiKey.order(:id).map { |k| k.attributes.except('last_used_at') },
      usages: ApiKeyUsage.order(:id).map(&:attributes)
    }
    ApiKeyUsage.delete_all
    ApiKey.delete_all
    User.delete_all
    snapshot
  end

  test '還原後資料與備份前相同 (含 id、時間戳、已撤銷的 key)' do
    snapshot = backup_and_wipe

    counts = AccountsBackup::Restore.new(@fs).call

    assert_equal({ 'users' => 1, 'api_keys' => 3, 'api_key_usages' => 1 }, counts)
    assert_equal snapshot[:users], User.order(:id).map(&:attributes)
    assert_equal(snapshot[:api_keys], ApiKey.order(:id).map { |k| k.attributes.except('last_used_at') })
    assert_equal snapshot[:usages], ApiKeyUsage.order(:id).map(&:attributes)
  end

  test '還原後 sync 不會誤判為重建,也不會重寫' do
    backup_and_wipe
    AccountsBackup::Restore.new(@fs).call

    assert_equal 0, AccountsBackup::Sync.new(@fs, now: 10.minutes.from_now).call.total
  end

  test '還原後原本的 key 可以照常驗證' do
    user = User.create!(provider: 'github', uid: '1')
    _key, token = ApiKey.generate!(user)
    AccountsBackup::Sync.new(@fs, now: 2.minutes.from_now).call
    ApiKey.delete_all
    User.delete_all

    AccountsBackup::Restore.new(@fs).call

    assert_not_nil ApiKey.authenticate(token)
  end

  test '本機 accounts DB 不是空的就拒絕還原' do
    backup_and_wipe
    User.create!(provider: 'github', uid: '99')

    error = assert_raises(AccountsBackup::Error) { AccountsBackup::Restore.new(@fs).call }
    assert_match 'users', error.message
  end

  test 'Firestore 上沒有備份時拒絕' do
    assert_raises(AccountsBackup::Error) { AccountsBackup::Restore.new(@fs).call }
  end
end
