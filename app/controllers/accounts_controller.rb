# frozen_string_literal: true

# 帳號頁: 顯示有效的 key 與「自己的」使用統計。
#
# 使用者自己的統計對「懷疑外流」很關鍵 —— 看到 last_used_at 是自己沒在用的
# 時間,才會知道該撤銷。所以自己的統計必須讓使用者看得到
# (全站統計則限 admin,見 ReportController)。
#
# 見 doc/api-key-design.md 5.4
class AccountsController < WebController
  USAGE_DAYS = 30

  before_action :require_sign_in!

  def show
    @api_keys = current_user.active_api_keys
    @revoked_api_keys = current_user.api_keys.where.not(revoked_at: nil)
                                    .order(revoked_at: :desc).limit(10)
    @usages = daily_usage
    @usage_total = @usages.sum { |_date, count| count }
  end

  private

  # 回傳 [[date, count], ...],最近的在前
  def daily_usage
    current_user.api_key_usages
                .where(used_on: (Date.current - (USAGE_DAYS - 1))..Date.current)
                .group(:used_on)
                .order(used_on: :desc)
                .sum(:count)
                .to_a
  end
end
