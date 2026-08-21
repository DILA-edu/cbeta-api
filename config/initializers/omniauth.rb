# frozen_string_literal: true

# Google / GitHub 登入。client id 與 secret 放 Rails credentials,不進版控:
#
#   bin/rails credentials:edit
#
#     google:
#       client_id: xxx
#       client_secret: xxx
#     github:
#       client_id: xxx
#       client_secret: xxx
#
# callback URL 要分別註冊各環境的網址(注意 sub-URI 前綴):
#   production: https://cbdata.dila.edu.tw/stable/auth/:provider/callback
#   staging:    https://cbdata.dila.edu.tw/dev/auth/:provider/callback
#   development: http://localhost:3000/auth/:provider/callback
#
# 見 doc/api-key-design.md 5.1、5.3
Rails.application.config.middleware.use OmniAuth::Builder do
  google = Rails.application.credentials.google || {}
  github = Rails.application.credentials.github || {}

  # scope 只要最小必要: 取得 provider 端的識別與 email。
  # 收集 email 的目的是必要時能聯絡對方(key 異常使用、服務變更通知)。
  provider :google_oauth2, google[:client_id], google[:client_secret],
           scope: 'email,profile',
           prompt: 'select_account'

  provider :github, github[:client_id], github[:client_secret],
           scope: 'user:email'
end

# OmniAuth 2 預設只接受 POST 進入 request phase(防 login CSRF),
# 搭配 omniauth-rails_csrf_protection 使用 button_to 送出。
OmniAuth.config.allowed_request_methods = [:post]

# 失敗不要丟例外(預設在 development 會 raise),統一導到 /auth/failure
OmniAuth.config.failure_raise_out_environments = []

OmniAuth.config.logger = Rails.logger
