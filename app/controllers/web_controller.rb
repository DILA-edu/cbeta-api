# frozen_string_literal: true

# 網頁端(登入、帳號與 key 管理、統計報表)的 base class。
#
# 為什麼不繼承 ApplicationController:
# ApplicationController 有 `skip_before_action :verify_authenticity_token`
# ——「整個 Controller 關閉 CSRF 檢查」,因為 API 回傳 JSON 需要 callback。
# OAuth 登入流程、以及「撤銷/重新產生 key」這些會改變狀態的操作,絕對不能在
# 關閉 CSRF 的 controller 下進行。
#
# 因此網頁端另開一支 base: 開啟 session、開啟 CSRF、不做 record_visit
# (record_visit 是 API 流量統計,網頁端不列入)。
#
# 見 doc/api-key-design.md 5.2
class WebController < ActionController::Base
  protect_from_forgery with: :exception

  helper_method :current_user, :signed_in?

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = session[:user_id] && User.find_by(id: session[:user_id])
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    return if signed_in?

    session[:return_to] = request.fullpath if request.get?
    redirect_to login_path, alert: '請先登入'
  end

  def require_admin!
    return require_sign_in! unless signed_in?
    return if current_user.admin?

    render plain: '403 Forbidden：本頁僅限管理者使用', status: :forbidden
  end

  def sign_in(user)
    reset_session # 防 session fixation
    session[:user_id] = user.id
    @current_user = user
  end

  def sign_out
    reset_session
    @current_user = nil
  end
end
