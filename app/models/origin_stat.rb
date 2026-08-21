# frozen_string_literal: true

# 每個 Origin 每天的 request 數。過渡期埋點,用途是在過渡期結束前確認:
# cbetaonline 的流量到底落在「命中白名單」還是「Origin 為 nil」。
# 若全部落在 nil,即可提前確認過渡期結束會出事。
#
# 見 doc/api-key-design.md 4.5
class OriginStat < AnalyticsRecord
  NONE = '(none)'

  attribute :count, :integer, default: 0

  # 用 upsert 累加,與 ApplicationController#record_visit 同一個模式。
  def self.record!(origin, used_on = Date.current)
    sql = <<~SQL.squish
      INSERT INTO origin_stats (origin, used_on, count)
      VALUES (?, ?, 1)
      ON CONFLICT (origin, used_on)
      DO UPDATE SET count = origin_stats.count + 1
    SQL

    connection.execute(
      sanitize_sql_array([sql, origin.presence || NONE, used_on])
    )
  end

  # 命中白名單的 Origin（用於判讀埋點結果）
  def allowlisted?
    Rails.configuration.api_origin_allowlist.include?(origin)
  end
end
