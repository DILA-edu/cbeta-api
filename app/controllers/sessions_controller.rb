# frozen_string_literal: true

# OAuth 登入 / 登出。
#
# 繼承 WebController(開啟 CSRF)—— OAuth 流程不能在關閉 CSRF 的
# ApplicationController 下進行。
class SessionsController < WebController
  # OmniAuth 的 callback 由 provider 導回,不會帶我們的 CSRF token。
  # request phase 的 CSRF 由 omniauth-rails_csrf_protection 負責
  # (登入頁用 button_to 以 POST 送出 /auth/:provider)。
  skip_before_action :verify_authenticity_token, only: %i[create failure]

  def new
    redirect_to account_path if signed_in?
  end

  def create
    auth = request.env['omniauth.auth']
    return redirect_to(login_path, alert: '登入失敗，請再試一次') if auth.blank?

    user = User.from_omniauth(auth)
    destination = session[:return_to] # sign_in 會 reset_session
    sign_in(user)

    redirect_to(destination.presence || account_path, notice: '登入成功')
  rescue ActiveRecord::RecordInvalid => e
    logger.warn "OmniAuth 登入失敗: #{e.message}"
    redirect_to login_path, alert: '登入失敗，請再試一次'
  end

  def failure
    message = params[:message].presence || 'unknown'
    logger.warn "OmniAuth failure: #{message}"
    redirect_to login_path, alert: '登入失敗或已取消'
  end

  def destroy
    sign_out
    redirect_to login_path, notice: '已登出'
  end
end
