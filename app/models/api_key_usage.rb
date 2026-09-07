# frozen_string_literal: true

# 每個 user、每把 key、每天的呼叫次數。只在「有帶 key」時記錄。
#
# 見 doc/api-key-design.md 4.4
class ApiKeyUsage < AccountsRecord
  belongs_to :user
  belongs_to :api_key

  attribute :count, :integer, default: 0

  # 用 upsert 累加,與 ApplicationController#record_visit 同一個模式。
  def self.record!(api_key, used_on = Date.current)
    sql = <<~SQL.squish
      INSERT INTO api_key_usages (user_id, api_key_id, used_on, count)
      VALUES (?, ?, ?, 1)
      ON CONFLICT (api_key_id, used_on)
      DO UPDATE SET count = api_key_usages.count + 1
    SQL

    connection.execute(
      sanitize_sql_array([sql, api_key.user_id, api_key.id, used_on])
    )
  end
end
