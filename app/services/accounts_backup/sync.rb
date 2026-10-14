# frozen_string_literal: true

module AccountsBackup
  # 把 accounts DB 有變更的列 upsert 到 Firestore。
  # 由 AccountsBackupJob (資料變更時) 與每日 cron 執行,見 AccountsBackup.run!。
  #
  # 用 watermark 判斷「有沒有變更」,沒有變更時只讀 1 次 meta、寫 0 次:
  #
  # - users / api_keys: 推 watermark < updated_at <= cutoff 的列。
  #   cutoff = 現在 - SETTLE_TIME,避免漏掉「updated_at 已決定、但 transaction
  #   還沒 commit」的列 (watermark 若直接取讀到的 max(updated_at),晚 commit
  #   但 updated_at 較早的列就永遠不會被推)。
  # - api_key_usages: 每次 request 都會累加,所以只推「已結束的日子」——
  #   那天過了就不會再變,每列只寫一次。
  #
  # 沒推任何列時不更新 watermark,下次重查同一段範圍 (本機查詢,成本可忽略)。
  # 若中途失敗,watermark 不會前進,下次重跑會再 upsert 一次,結果相同。
  #
  # 刪除不在這裡處理,見 AccountsBackup::Prune。
  class Sync
    SETTLE_TIME = 1.minute

    Result = Struct.new(:counts, :meta, keyword_init: true) do
      def total = counts.values.sum
    end

    # full: 忽略 watermark,整份重推。從 pg_dump 還原後用 —— 還原回來的列
    # updated_at 都比 watermark 舊,不重推的話 Firestore 會缺少被 Prune 刪掉的資料。
    def initialize(client, now: Time.current, full: false)
      @client = client
      @now = now
      @full = full
    end

    def call
      meta = @client.get(META_COLLECTION, META_DOC)
      AccountsBackup.check_env!(meta)
      check_not_reset!(meta)

      cutoff = @now - SETTLE_TIME
      usage_through = (cutoff.to_date - 1)

      writes = []
      counts = {}
      %w[users api_keys].each do |table|
        rows = changed_rows(table, watermark(meta, 'updated_through'), cutoff)
        counts[table] = rows.size
        writes.concat(rows.map { |r| [ table, r.id.to_s, AccountsBackup.serialize(table, r) ] })
      end

      usages = finished_usages(watermark(meta, 'usage_through'), usage_through)
      counts['api_key_usages'] = usages.size
      writes.concat(usages.map { |r| [ 'api_key_usages', r.id.to_s, AccountsBackup.serialize('api_key_usages', r) ] })

      return Result.new(counts:, meta:) if writes.empty?

      @client.upsert_all(writes)

      # watermark 一定在資料之後才寫,中途失敗時才能安全重跑
      new_meta = build_meta(meta, cutoff, usages.any? ? usage_through : nil)
      @client.upsert_all([ [ META_COLLECTION, META_DOC, new_meta ] ])
      Result.new(counts:, meta: new_meta)
    end

    private

    def watermark(meta, key)
      @full ? nil : meta&.dig(key)
    end

    def changed_rows(table, watermark, cutoff)
      scope = AccountsBackup.model_for(table).where(updated_at: ..cutoff)
      scope = scope.where('updated_at > ?', watermark) if watermark
      scope.order(:id).to_a
    end

    def finished_usages(watermark, through)
      scope = ApiKeyUsage.where(used_on: ..through)
      scope = scope.where(used_on: (Date.iso8601(watermark) + 1)..) if watermark
      scope.order(:id).to_a
    end

    SENTINEL_TABLES = %w[users api_keys].freeze

    # 偵測 accounts DB 是否被重建過 (例如誤刪後重新 migrate)。重建後 id 從 1
    # 重新開始,繼續 sync 的話,新的 id 1 號就會覆寫備份裡原本的 id 1 號。
    #
    # 做法: meta 記住第一次備份時 id 最小那一列 (哨兵) 的 id 與 created_at。
    # PostgreSQL 的 id 不會重複使用,所以本機同一個 id 的 created_at 不同,
    # 就代表 DB 被重建過。哨兵被合法刪除 (本機沒有該 id) 則略過,不誤判。
    def check_not_reset!(meta)
      return if meta.nil?

      SENTINEL_TABLES.each do |table|
        id = meta["sentinel_#{table}_id"]
        next if id.nil?

        local = AccountsBackup.model_for(table).find_by(id:)
        next if local.nil? || local.created_at.utc.iso8601(6) == meta["sentinel_#{table}_created_at"].utc.iso8601(6)

        raise Error, "本機 #{table} id=#{id} 的 created_at 與備份不同,accounts DB 看起來被重建過。" \
                     '為避免覆寫備份,已中止;請先確認是否需要 rake accounts_backup:restore'
      end
    end

    # 哨兵一旦設定就不再變;該表第一次有資料時才設定
    def sentinel_fields(meta)
      SENTINEL_TABLES.each_with_object({}) do |table, fields|
        id_key = "sentinel_#{table}_id"
        at_key = "sentinel_#{table}_created_at"
        if meta&.dig(id_key)
          fields[id_key] = meta[id_key]
          fields[at_key] = meta[at_key]
        elsif (first = AccountsBackup.model_for(table).order(:id).first)
          fields[id_key] = first.id
          fields[at_key] = first.created_at
        end
      end
    end

    def build_meta(meta, cutoff, usage_through)
      {
        'rails_env' => Rails.env,
        'updated_through' => cutoff,
        'usage_through' => usage_through&.iso8601 || meta&.dig('usage_through'),
        'synced_at' => @now
      }.merge(sentinel_fields(meta))
    end
  end
end
