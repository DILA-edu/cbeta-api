# frozen_string_literal: true

module AccountsBackup
  # 從 Firestore 把 users / api_keys / api_key_usages 下載回本機 accounts DB。
  #
  # - 只寫進「空的」accounts DB。不做合併、也不提供強制覆寫: 要覆寫請先
  #   自己清空,讓這個不可逆的動作必須是人刻意做的。
  # - id 與 created_at / updated_at 原樣寫回,外鍵與 watermark 才對得上。
  # - 用 insert_all 而非 create!: ApiKey 的「同時最多 2 把有效 key」validation
  #   是針對新建的規則,不適用於還原歷史資料 (已撤銷的 key 也要還原)。
  class Restore
    def initialize(client)
      @client = client
    end

    # 回傳 { table => 筆數 }
    def call
      meta = @client.get(META_COLLECTION, META_DOC)
      raise Error, 'Firestore 上沒有備份 (找不到 meta/sync)' if meta.nil?

      AccountsBackup.check_env!(meta)
      check_empty!

      docs = TABLES.keys.index_with { |table| @client.list(table) }

      AccountsRecord.transaction do
        # 順序: users → api_keys → api_key_usages,符合外鍵方向
        TABLES.each_key do |table|
          rows = docs[table].values.map { |fields| restore_row(table, fields) }
          AccountsBackup.model_for(table).insert_all!(rows) if rows.any?
        end
      end

      reset_sequences!
      docs.transform_values(&:size)
    end

    private

    def restore_row(table, fields)
      row = fields.slice(*TABLES[table])
      row['used_on'] = Date.iso8601(row['used_on']) if row.key?('used_on')
      row
    end

    def check_empty!
      non_empty = TABLES.keys.select { |table| AccountsBackup.model_for(table).exists? }
      return if non_empty.empty?

      raise Error, "本機 accounts DB 不是空的 (#{non_empty.join(', ')} 有資料),不做還原。" \
                   '確定要以備份覆蓋時,請先自行清空這幾張表'
    end

    # 明確指定 id 寫入後,PostgreSQL 的 sequence 不會跟著前進,
    # 不重設的話下一筆 INSERT 會撞 primary key。
    def reset_sequences!
      connection = AccountsRecord.connection
      return unless connection.respond_to?(:reset_pk_sequence!)

      TABLES.each_key { |table| connection.reset_pk_sequence!(table) }
    end
  end
end
