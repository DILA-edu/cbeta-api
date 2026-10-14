# frozen_string_literal: true

# users / api_keys 有變更時,把 accounts DB 備份到 Firestore。
# 由 AccountsBackupTrigger (model 的 after_commit) 排入。
#
# 跑在 :async adapter (web process 內的 thread),不需要常駐 worker。
# 代價是 Passenger 關掉 process 時,還沒跑的 job 會遺失、也不會重試 ——
# 由每日 cron (rake accounts_backup:sync) 補上。見 doc/accounts-backup.md
class AccountsBackupJob < ApplicationJob
  queue_as :default

  # 網路或 Firestore 暫時性錯誤。重試也只在同一個 process 內有效。
  retry_on AccountsBackup::FirestoreClient::Error, wait: 5.minutes, attempts: 3

  # 環境不符、DB 重建、刪除超過上限: 重試也沒用,要人處理
  discard_on AccountsBackup::Error do |_job, error|
    Rails.logger.error "[AccountsBackup] #{error.message}"
  end

  def perform
    return unless AccountsBackup.enabled?

    result = AccountsBackup.run!(AccountsBackup.client)
    Rails.logger.info "[AccountsBackup] #{result}" if result.present?
  end
end
