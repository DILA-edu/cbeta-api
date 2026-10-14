# frozen_string_literal: true

# accounts DB (users / api_keys / api_key_usages) 備份到 Firebase (Firestore)。
#
# - 平常完全不讀 Firestore,request path 也不碰它。
# - users / api_keys 有變更時由 AccountsBackupJob 備份,每日 cron 再跑一次保底。
# - 只在資料有變更時才寫 (watermark,見 AccountsBackup::Sync);
#   本機刪除的 user 從備份刪除 (見 AccountsBackup::Prune)。
# - staging / production 各自備份到不同的 Firestore DB,設定放 config/cb.yml
#   (gitignored,每台機器一份) 的 firebase_backup 區塊,沒設就是停用。
#
# 見 doc/accounts-backup.md
module AccountsBackup
  META_COLLECTION = 'meta'
  META_DOC = 'sync'

  # 每張表要備份的欄位。
  #
  # 刻意不備份 api_keys.last_used_at: 它由 touch_last_used! 用 update_column
  # 寫入,不會動 updated_at,納入的話就無法用 updated_at 判斷「有沒有變更」。
  # restore 後為 nil,下次使用時就會補上。
  TABLES = {
    'users' => %w[id provider uid email name admin created_at updated_at],
    'api_keys' => %w[id user_id token_digest token_hint revoked_at created_at updated_at],
    'api_key_usages' => %w[id user_id api_key_id used_on count]
  }.freeze

  MODELS = { 'users' => 'User', 'api_keys' => 'ApiKey', 'api_key_usages' => 'ApiKeyUsage' }.freeze

  Config = Struct.new(:project_id, :database_id, :credentials, keyword_init: true)

  class Error < StandardError; end

  # cb.yml 沒有 firebase_backup 區塊時回 nil (= 停用)
  def self.config
    raw = Rails.configuration.cb.firebase_backup
    return nil if raw.blank?

    raw = raw.symbolize_keys
    Config.new(
      project_id: raw.fetch(:project_id),
      database_id: raw[:database_id].presence || '(default)',
      credentials: raw.fetch(:credentials)
    )
  end

  def self.enabled?
    config.present?
  end

  # 推送變更 + 同步刪除。job 與 rake 共用。
  # 回傳 { table => 筆數 },只含有異動的表
  def self.run!(client, max_prune: nil, full: false)
    synced = Sync.new(client, full:).call.counts.select { |_, n| n.positive? }
    pruned = Prune.new(client, max_users: max_prune).call
    synced.transform_keys { |t| "#{t} synced" }.merge(pruned.transform_keys { |t| "#{t} pruned" })
  end

  def self.client
    cfg = config or raise Error, 'config/cb.yml 沒有 firebase_backup 設定 (目前環境: ' \
                                 "#{Rails.env}),備份功能停用中"
    FirestoreClient.from_config(cfg)
  end

  def self.model_for(table)
    MODELS.fetch(table).constantize
  end

  # record → 要寫進 Firestore 的 fields。Date 存成 'YYYY-MM-DD' 字串。
  def self.serialize(table, record)
    TABLES.fetch(table).to_h do |column|
      value = record.public_send(column)
      value = value.iso8601 if value.is_a?(Date) && !value.is_a?(DateTime)
      [ column, value ]
    end
  end

  # 每個 Firestore DB 都記錄它屬於哪個 Rails.env,sync / restore 開頭比對。
  # 防止 staging 的 cb.yml 抄錯,把 staging 資料寫進 production 的備份 (或反向)。
  def self.check_env!(meta)
    return if meta.nil? || meta['rails_env'] == Rails.env

    raise Error, "這個 Firestore DB 屬於 #{meta['rails_env'].inspect},目前是 #{Rails.env} —— " \
                 'cb.yml 的 firebase_backup 是不是設錯了?'
  end
end
