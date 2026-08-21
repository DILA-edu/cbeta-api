# frozen_string_literal: true

require 'test_helper'

# API key 驗證的行為表（設計文件 3.2）。
#
# 用 chinese_tools/sc2tc 當受測 endpoint —— 它已納管、不需要 CBETA 資料、
# 回應簡單。
class ApiKeyAuthenticationTest < ActionDispatch::IntegrationTest
  ENDPOINT = '/chinese_tools/sc2tc'
  ALLOWED_ORIGIN = 'https://cbetaonline.dila.edu.tw'

  setup do
    @user = User.create!(provider: 'github', uid: '1')
    @api_key, @token = ApiKey.generate!(@user)

    @original_allowlist = Rails.configuration.api_origin_allowlist
    @original_required = Rails.configuration.api_key_required
    Rails.configuration.api_origin_allowlist = [ALLOWED_ORIGIN]
    Rails.configuration.api_key_required = false
  end

  teardown do
    Rails.configuration.api_origin_allowlist = @original_allowlist
    Rails.configuration.api_key_required = @original_required
  end

  def bearer(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def end_transition!
    Rails.configuration.api_key_required = true
  end

  def error_code
    JSON.parse(response.body).dig('error', 'code')
  end

  # --- 有帶 key ---

  test '有效的 key 放行' do
    get ENDPOINT, params: { q: '简' }, headers: bearer(@token)
    assert_response :success
  end

  test '無效的 key 回 401' do
    get ENDPOINT, params: { q: '简' }, headers: bearer('cbeta_bogus')
    assert_response :unauthorized
    assert_equal 401, error_code
  end

  test '已撤銷的 key 回 401' do
    @api_key.revoke!
    get ENDPOINT, params: { q: '简' }, headers: bearer(@token)
    assert_response :unauthorized
  end

  test '無效的 key 即使 Origin 命中白名單也回 401' do
    get ENDPOINT, params: { q: '简' },
                  headers: bearer('cbeta_bogus').merge('Origin' => ALLOWED_ORIGIN)
    assert_response :unauthorized
  end

  test '401 帶 WWW-Authenticate header' do
    get ENDPOINT, params: { q: '简' }, headers: bearer('cbeta_bogus')
    assert_equal 'Bearer realm="CBETA API"', response.headers['WWW-Authenticate']
  end

  test 'Bearer 大小寫不敏感' do
    get ENDPOINT, params: { q: '简' }, headers: { 'Authorization' => "bearer #{@token}" }
    assert_response :success
  end

  test '非 Bearer 的 Authorization 視為未帶 key' do
    get ENDPOINT, params: { q: '简' }, headers: { 'Authorization' => 'Basic abc' }
    assert_response :success # 過渡期放行
    assert_equal 'recommended', response.headers['X-CBETA-API-Key']
  end

  # --- 未帶 key ---

  test '未帶 key、Origin 命中白名單 → 放行,且不加提示 header' do
    get ENDPOINT, params: { q: '简' }, headers: { 'Origin' => ALLOWED_ORIGIN }
    assert_response :success
    assert_nil response.headers['X-CBETA-API-Key']
  end

  test '未帶 key、Origin 為 nil → 過渡期放行並加提示 header' do
    get ENDPOINT, params: { q: '简' }
    assert_response :success
    assert_equal 'recommended', response.headers['X-CBETA-API-Key']
  end

  test '未帶 key、Origin 不在白名單 → 過渡期放行' do
    get ENDPOINT, params: { q: '简' }, headers: { 'Origin' => 'https://evil.example.com' }
    assert_response :success
    assert_equal 'recommended', response.headers['X-CBETA-API-Key']
  end

  test 'Origin 比對是完整字串,不做 subdomain 模糊比對' do
    end_transition!
    get ENDPOINT, params: { q: '简' },
                  headers: { 'Origin' => 'https://evil.cbetaonline.dila.edu.tw' }
    assert_response :unauthorized
  end

  test 'Origin 比對含 scheme —— http 不等於 https' do
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: { 'Origin' => 'http://cbetaonline.dila.edu.tw' }
    assert_response :unauthorized
  end

  # --- 過渡期結束後 ---

  test '過渡期結束後,未帶 key 且 Origin 為 nil → 401' do
    end_transition!
    get ENDPOINT, params: { q: '简' }
    assert_response :unauthorized
  end

  test '過渡期結束後,未帶 key 但 Origin 命中白名單 → 仍放行' do
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: { 'Origin' => ALLOWED_ORIGIN }
    assert_response :success
  end

  test '過渡期結束後,有效的 key → 放行' do
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: bearer(@token)
    assert_response :success
  end

  # --- key 只能走 header ---

  test '不接受 query param 傳 key' do
    end_transition!
    get ENDPOINT, params: { q: '简', api_key: @token }
    assert_response :unauthorized
  end

  # --- JSONP ---

  test '錯誤回應支援 callback 包裝' do
    get ENDPOINT, params: { q: '简', callback: 'myCallback' }, headers: bearer('cbeta_bogus')
    assert_response :unauthorized
    assert_equal 'application/javascript', response.media_type
    # Rails 會在前面加 /**/（Rosetta-Flash 的防護）
    assert_match(%r{\A/\*\*/myCallback\(}, response.body)
  end

  test '不安全的 callback 不反射進回應' do
    get ENDPOINT, params: { q: '简', callback: '<script>alert(1)</script>' },
                  headers: bearer('cbeta_bogus')
    assert_response :unauthorized
    assert_equal 'application/json', response.media_type
    assert_no_match(/script/, response.body)
  end

  # --- 使用量記錄 ---

  test '帶 key 才記使用量' do
    assert_difference 'ApiKeyUsage.count', 1 do
      get ENDPOINT, params: { q: '简' }, headers: bearer(@token)
    end

    assert_no_difference 'ApiKeyUsage.count' do
      get ENDPOINT, params: { q: '简' }
    end
  end

  test '同一天多次呼叫累加在同一列' do
    3.times { get ENDPOINT, params: { q: '简' }, headers: bearer(@token) }

    assert_equal 1, ApiKeyUsage.count
    assert_equal 3, ApiKeyUsage.sole.count
  end

  test '帶 key 會更新 last_used_at' do
    assert_nil @api_key.last_used_at
    get ENDPOINT, params: { q: '简' }, headers: bearer(@token)
    assert_not_nil @api_key.reload.last_used_at
  end

  # --- 不納管的 endpoint ---

  test '/health 不納管' do
    end_transition!
    get '/health'
    assert_response :success
  end

  test 'static_pages 不納管' do
    end_transition!
    get '/static_pages/download'
    assert_response :success
  end

  test '登入頁不納管' do
    end_transition!
    get login_path
    assert_response :success
  end
end
