# frozen_string_literal: true

require 'test_helper'

class AccountsBackupJobTest < ActiveJob::TestCase
  # 測試環境沒有 firebase_backup 設定;需要「啟用」時暫時塞一份假的
  def with_backup_enabled
    cb = Rails.configuration.cb
    original = cb.firebase_backup
    cb.firebase_backup = { project_id: 'p', credentials: '/nonexistent.json' }
    yield
  ensure
    cb.firebase_backup = original
  end

  test '未設定時不排 job' do
    assert_no_enqueued_jobs { User.create!(provider: 'github', uid: '1') }
  end

  test '建立 user、產生與撤銷 key、刪除 user 時排 job,且延後執行' do
    with_backup_enabled do
      user = nil
      assert_enqueued_with(job: AccountsBackupJob, at: AccountsBackupTrigger.job_delay.from_now) do
        user = User.create!(provider: 'github', uid: '1')
      end

      key = nil
      assert_enqueued_jobs(1) { key, _ = ApiKey.generate!(user) }
      assert_enqueued_jobs(1) { key.revoke! }
      assert_enqueued_jobs(2) { user.destroy! } # user 與連帶刪除的 key 各一
    end
  end

  test '沒有變更的 save (每次登入) 與 last_used_at 更新不排 job' do
    user = User.create!(provider: 'github', uid: '1', email: 'a@example.com')
    key, _ = ApiKey.generate!(user)

    with_backup_enabled do
      assert_no_enqueued_jobs do
        user.update!(email: 'a@example.com')
        key.touch_last_used!
      end
    end
  end

  test 'cb.yml 的 firebase_backup 寫錯時,不影響建立 user (不排 job、不 raise)' do
    cb = Rails.configuration.cb
    original = cb.firebase_backup
    cb.firebase_backup = { credentials: 'x' } # 少了 project_id

    assert_no_enqueued_jobs do
      assert_nothing_raised { User.create!(provider: 'github', uid: '1') }
    end
  ensure
    cb.firebase_backup = original
  end

  # 曾經因循環 autoload,先載入的 model 才掛得上 callback
  test 'User 與 ApiKey 都掛上 after_commit' do
    [ User, ApiKey ].each do |model|
      assert_includes model.__callbacks[:commit].map(&:filter), :enqueue_accounts_backup, model.name
    end
  end

  test '未設定時 job 什麼都不做' do
    assert_nothing_raised { AccountsBackupJob.perform_now }
  end
end
