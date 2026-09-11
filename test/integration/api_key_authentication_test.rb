# frozen_string_literal: true

require 'test_helper'

# API key 驗證的行為表（設計文件 3.2）。
#
# 用 chinese_tools/sc2tc 當受測 endpoint —— 它已納管、不需要 CBETA 資料、
# 回應簡單。
class ApiKeyAuthenticationTest < ActionDispatch::IntegrationTest
  ENDPOINT = '/chinese_tools/sc2tc'
  # 用假的 Origin —— 測試本來就會覆寫 config.api_origin_allowlist，
  # 而真實的白名單不進版控（見 doc/api-key-design.md 3.3）。
  ALLOWED_ORIGIN = 'https://allowed.example.com'
  # 校內 IP 也用假的 —— 真實範圍不進版控（見 doc/api-key-design.md 3.4）。
  # 203.0.113.0/24 是 RFC 5737 保留給文件用的 TEST-NET-3。
  INTERNAL_RANGE = '203.0.113.0/24'
  INTERNAL_IP = '203.0.113.7'
  OUTSIDE_IP = '198.51.100.7'

  setup do
    @user = User.create!(provider: 'github', uid: '1')
    @api_key, @token = ApiKey.generate!(@user)

    @original_allowlist = Rails.configuration.api_origin_allowlist
    @original_required = Rails.configuration.api_key_required
    @original_internal = Rails.configuration.api_internal_ip_ranges
    Rails.configuration.api_origin_allowlist = [ALLOWED_ORIGIN]
    Rails.configuration.api_key_required = false
    Rails.configuration.api_internal_ip_ranges = [IPAddr.new(INTERNAL_RANGE)]
  end

  teardown do
    Rails.configuration.api_origin_allowlist = @original_allowlist
    Rails.configuration.api_key_required = @original_required
    Rails.configuration.api_internal_ip_ranges = @original_internal
  end

  # 從校內 IP 發出的 request
  def from_internal(headers = {})
    { 'REMOTE_ADDR' => INTERNAL_IP }.merge(headers)
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
                  headers: { 'Origin' => 'https://evil.allowed.example.com' }
    assert_response :unauthorized
  end

  test 'Origin 比對含 scheme —— http 不等於 https' do
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: { 'Origin' => 'http://allowed.example.com' }
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

  # --- 校內 IP（設計文件 3.4）---

  test '校內 IP 未帶 key → 放行,且不加提示 header' do
    # 提示 header 的意思是「過渡期結束後你會壞掉」,對校內並不成立
    get ENDPOINT, params: { q: '简' }, headers: from_internal
    assert_response :success
    assert_nil response.headers['X-CBETA-API-Key']
  end

  test '過渡期結束後,校內 IP 未帶 key → 仍放行' do
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: from_internal
    assert_response :success
  end

  test '校內 IP 帶有效的 key → 放行' do
    get ENDPOINT, params: { q: '简' }, headers: from_internal(bearer(@token))
    assert_response :success
  end

  test '校內 IP 帶無效的 key → 仍然 401' do
    # 帶了 key 就一定驗證,校內也不例外: 那通常是 client 設定錯誤
    get ENDPOINT, params: { q: '简' }, headers: from_internal(bearer('cbeta_bogus'))
    assert_response :unauthorized
  end

  test '範圍外的 IP 不算校內' do
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: { 'REMOTE_ADDR' => OUTSIDE_IP }
    assert_response :unauthorized
  end

  test '偽造 X-Forwarded-For 不能冒充校內 IP' do
    # 判斷用 remote_addr（TCP 對端）而非 remote_ip。remote_ip 會優先採信
    # client 送來的 X-Forwarded-For,本站前面沒有反向 proxy,那個 header
    # 必定是偽造的。若有人日後把判斷改回 remote_ip,這個測試要擋下來。
    end_transition!
    get ENDPOINT, params: { q: '简' },
                  headers: { 'REMOTE_ADDR' => OUTSIDE_IP,
                             'HTTP_X_FORWARDED_FOR' => INTERNAL_IP }
    assert_response :unauthorized
  end

  test '校內 IP 範圍為空時,不豁免任何人' do
    Rails.configuration.api_internal_ip_ranges = []
    end_transition!
    get ENDPOINT, params: { q: '简' }, headers: from_internal
    assert_response :unauthorized
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
