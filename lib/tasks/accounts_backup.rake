# accounts DB 備份到 Firebase (Firestore)。見 doc/accounts-backup.md
namespace :accounts_backup do
  desc '把 accounts DB 的變更推到 Firestore,並刪除本機已刪的 user (每日 cron 保底;沒變更就不寫)'
  task sync: :environment do
    # 沒設定時安靜離開,不要每次都寄 cron mail
    next unless AccountsBackup.enabled?

    max_prune = ENV['MAX_PRUNE']&.to_i
    # FULL=1: 忽略 watermark 整份重推 (從 pg_dump 還原後用)
    result = AccountsBackup.run!(AccountsBackup.client, max_prune:, full: ENV['FULL'].present?)
    if result.any?
      summary = result.map { |table, n| "#{table}=#{n}" }.join(' ')
      Rails.logger.info "[AccountsBackup] #{summary}"
      puts "#{Time.current.iso8601} #{summary}"
    end
  rescue AccountsBackup::Error, AccountsBackup::FirestoreClient::Error => e
    Rails.logger.error "[AccountsBackup] #{e.message}"
    abort "accounts_backup:sync 失敗: #{e.message}"
  end

  desc '從 Firestore 還原到「空的」accounts DB'
  task restore: :environment do
    puts "RAILS_ENV: #{Rails.env}"
    puts "accounts DB: #{AccountsRecord.connection_db_config.database}"
    counts = AccountsBackup::Restore.new(AccountsBackup.client).call
    counts.each { |table, n| puts "  #{table}: #{n} 筆" }
    puts '還原完成。'
  rescue AccountsBackup::Error, AccountsBackup::FirestoreClient::Error => e
    abort "accounts_backup:restore 失敗: #{e.message}"
  end

  desc '顯示備份設定與 Firestore 上的 watermark (唯讀)'
  task status: :environment do
    config = AccountsBackup.config
    puts "RAILS_ENV: #{Rails.env}"
    puts "accounts DB: #{AccountsRecord.connection_db_config.database}"
    if config.nil?
      puts 'firebase_backup: (未設定,備份停用)'
      next
    end

    puts "firebase_backup: project=#{config.project_id} database=#{config.database_id}"
    meta = AccountsBackup.client.get(AccountsBackup::META_COLLECTION, AccountsBackup::META_DOC)
    if meta.nil?
      puts '  Firestore 上尚無備份 (還沒跑過 sync)'
    else
      meta.sort.each { |k, v| puts "  #{k}: #{v}" }
      AccountsBackup.check_env!(meta)
    end
    puts "本機: users #{User.count}、api_keys #{ApiKey.count}、api_key_usages #{ApiKeyUsage.count}"
  rescue AccountsBackup::Error, AccountsBackup::FirestoreClient::Error => e
    abort "⚠️ #{e.message}"
  end
end
