# frozen_string_literal: true

# 資料有變更時排入 AccountsBackupJob,把 accounts DB 備份到 Firestore。
#
# - 不在 request 裡呼叫 Firestore,登入、建 key 不會變慢,Firestore 出狀況也不影響。
# - 延後執行: Sync 會略過 SETTLE_TIME 內才更新的列,太早跑會看不到剛 commit 的這筆。
# - 重複排入沒關係 (例如刪 user 時連帶刪多把 key): Sync 沒有變更就不寫。
# - touch_last_used! (update_column) 與 ApiKeyUsage.record! (raw SQL)
#   不會觸發 callback,所以一般 API request 不會排 job。
module AccountsBackupTrigger
  extend ActiveSupport::Concern

  included do
    # User.from_omniauth 每次登入都會 save!,沒有變更時不排 job
    after_commit :enqueue_accounts_backup, if: -> { destroyed? || saved_changes? }
  end

  # 刻意不寫成常數: 這個 module 載入時若去讀 AccountsBackup::Sync,
  # 會在 model 載入途中又 autoload 回 model,造成另一個 model 拿到
  # 還沒定義完的 concern,after_commit 就掛不上去。
  def self.job_delay
    AccountsBackup::Sync::SETTLE_TIME + 1.minute
  end

  private

  # after_commit 的例外會往上丟: 資料已經 commit,controller 卻拿到 500。
  # 備份是附帶功能,cb.yml 設定寫錯也不能讓登入、建 key 壞掉,所以全部吞掉只留 log。
  def enqueue_accounts_backup
    return unless AccountsBackup.enabled?

    AccountsBackupJob.set(wait: AccountsBackupTrigger.job_delay).perform_later
  rescue StandardError => e
    Rails.logger.error "[AccountsBackup] 排入備份 job 失敗: #{e.class}: #{e.message}"
  end
end
