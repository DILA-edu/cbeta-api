# frozen_string_literal: true

# 產生 / 撤銷自己的 API key。
#
# 明文只在 create 之後顯示一次(放 flash,不入 DB、不寫 log)。
class ApiKeysController < WebController
  before_action :require_sign_in!

  def create
    unless current_user.can_create_api_key?
      return redirect_to account_path,
                        alert: "同時最多只能有 #{User::MAX_ACTIVE_API_KEYS} 把有效的 API key，請先撤銷舊的"
    end

    _api_key, token = ApiKey.generate!(current_user)
    # 明文只在此顯示一次。放 flash 而非 session,避免留在 cookie 裡。
    flash[:new_api_key] = token
    redirect_to account_path, notice: 'API key 已產生，請立刻複製保存'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to account_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    api_key = current_user.api_keys.find(params[:id])

    if api_key.revoke!
      redirect_to account_path, notice: '已撤銷該 API key，立即失效'
    else
      redirect_to account_path, alert: '該 API key 已經撤銷過了'
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to account_path, alert: '查無此 API key'
  end
end
