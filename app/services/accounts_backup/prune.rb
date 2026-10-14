# frozen_string_literal: true

module AccountsBackup
  # 本機已刪除的 user,連同他的 api_keys 與 api_key_usages,從 Firestore 刪除。
  #
  # 以 users 為單位: api_keys 只會撤銷 (軟刪除),不會單獨被刪,
  # 所以只有 user 被 destroy 時才需要清掉他的 key 與使用紀錄。
  #
  # 「本機沒有就刪」這種比對,在本機 DB 出問題時 (被誤清空、database.yml
  # 指錯 DB) 會把備份一起清掉,因此有兩道保險:
  # - 本機 users 是空的 → 不刪,中止
  # - 一次要刪的 user 超過 max_users,或超過本機剩下的 user 數 → 不刪,中止,
  #   留給人判斷。後者是給 user 很少的環境 (staging): DB 重建後只有 1 個新帳號、
  #   備份裡有 8 個時,8 < 10 擋不住,但 8 > 1 擋得住。
  # 真的被清掉時,還有 server 上每日 pg_dump 保留 7 份可以救 (見 doc)。
  class Prune
    MAX_USERS = 10

    # max_users: nil 時上限為 min(MAX_USERS, 本機剩下的 user 數);
    # 明確指定 (rake 的 MAX_PRUNE) 時就以它為準,給人確認後放行用
    def initialize(client, max_users: nil)
      @client = client
      @max_users = max_users
    end

    # 回傳 { table => 刪除筆數 }
    def call
      meta = @client.get(META_COLLECTION, META_DOC)
      return {} if meta.nil? # 還沒有備份

      AccountsBackup.check_env!(meta)

      local_ids = User.pluck(:id).to_set(&:to_s)
      gone = @client.list('users').keys.reject { |id| local_ids.include?(id) }
      return {} if gone.empty?

      check_safe!(local_ids, gone)

      deletes = gone.flat_map do |id|
        [ [ 'users', id ] ] +
          %w[api_keys api_key_usages].flat_map do |table|
            @client.query_ids(table, 'user_id', id.to_i).map { |doc_id| [ table, doc_id ] }
          end
      end
      @client.delete_all(deletes)
      deletes.group_by(&:first).transform_values(&:size)
    end

    private

    def check_safe!(local_ids, gone)
      if local_ids.empty?
        raise Error, '本機 users 是空的,但備份裡有資料。accounts DB 可能被清空或 database.yml 指錯,' \
                     '不刪除備份;請先確認是否需要 rake accounts_backup:restore'
      end
      limit = @max_users || [ MAX_USERS, local_ids.size ].min
      return if gone.size <= limit

      raise Error, "這次要從備份刪除 #{gone.size} 個 user,超過上限 #{limit} " \
                   "(預設為 #{MAX_USERS} 與本機剩下的 #{local_ids.size} 個取小者),已中止。" \
                   '確認是刻意刪除後,用 MAX_PRUNE=<數量> 重跑 rake accounts_backup:sync'
    end
  end
end
