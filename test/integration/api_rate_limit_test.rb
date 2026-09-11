# frozen_string_literal: true

require 'test_helper'

# rate limit（設計文件 6）。
#
# test 環境的 cache_store 是 null_store（increment 回 nil），rate limit 形同
# 停用 —— 否則整個測試套件都會受 60/min 的限制影響而變得不穩定。
# 這裡把 Rails.cache 換成 MemoryStore 來實測。
class ApiRateLimitTest < ActionDispatch::IntegrationTest
  # 用 /changes 當受測 endpoint: 它已納管,而且參數空白時會立刻回應,
  # 不碰資料庫也不呼叫外部程式 —— 這個測試要打數百次請求,endpoint 的成本
  # 直接決定測試時間。
  ENDPOINT = '/changes'

  # 校內 IP 用假的 —— 真實範圍不進版控。203.0.113.0/24 是 RFC 5737 的 TEST-NET-3。
  INTERNAL_RANGE = '203.0.113.0/24'
  INTERNAL_IP = '203.0.113.7'

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    @user = User.create!(provider: 'github', uid: '1')
    _api_key, @token = ApiKey.generate!(@user)

    # 預設沒有校內 IP,既有的 test 才不受影響
    @original_internal = Rails.configuration.api_internal_ip_ranges
    Rails.configuration.api_internal_ip_ranges = []
  end

  teardown do
    Rails.cache = @original_cache
    Rails.configuration.api_internal_ip_ranges = @original_internal
  end

  def call(headers: {})
    get ENDPOINT, headers:
  end

  def internal!
    Rails.configuration.api_internal_ip_ranges = [IPAddr.new(INTERNAL_RANGE)]
  end

  def from_internal
    { 'REMOTE_ADDR' => INTERNAL_IP }
  end

  def bearer
    { 'Authorization' => "Bearer #{@token}" }
  end

  test '未帶 key 在額度內放行' do
    ApiKeyAuthentication::ANONYMOUS_LIMIT.times do
      call
      assert_response :success
    end
  end

  test '未帶 key 超過額度回 429' do
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 1).times { call }
    assert_response :too_many_requests
    assert_equal 429, JSON.parse(response.body).dig('error', 'code')
  end

  test '429 帶 Retry-After' do
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 1).times { call }
    assert_equal ApiKeyAuthentication::RATE_LIMIT_WINDOW.to_i.to_s,
                 response.headers['Retry-After']
  end

  test '未帶 key 的 429 訊息提示可申請 key 取得較高額度' do
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 1).times { call }
    assert_match 'API key', JSON.parse(response.body).dig('error', 'message')
  end

  test '帶 key 的額度高於未帶 key' do
    assert ApiKeyAuthentication::KEYED_LIMIT > ApiKeyAuthentication::ANONYMOUS_LIMIT

    # 超過未帶 key 的額度之後,帶 key 仍然放行
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 10).times { call(headers: bearer) }
    assert_response :success
  end

  test '帶 key 超過自己的額度也會 429' do
    (ApiKeyAuthentication::KEYED_LIMIT + 1).times { call(headers: bearer) }
    assert_response :too_many_requests
  end

  test '未帶 key 用滿額度後,帶 key 不受影響' do
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 1).times { call }
    assert_response :too_many_requests

    call(headers: bearer)
    assert_response :success
  end

  test '額度跨 controller 共用' do
    # 預設的 scope 是 controller_path,那會變成每個 controller 各有一份額度。
    # 這裡先把 ENDPOINT 用掉大部分,再換另一支已納管的 controller 用完剩下的。
    ApiKeyAuthentication::ANONYMOUS_LIMIT.times { call }
    assert_response :success

    get '/chinese_tools/sc2tc', params: { q: '简' }
    assert_response :too_many_requests
  end

  test '不同 user 各有自己的額度' do
    other = User.create!(provider: 'github', uid: '2')
    _key, other_token = ApiKey.generate!(other)

    (ApiKeyAuthentication::KEYED_LIMIT + 1).times { call(headers: bearer) }
    assert_response :too_many_requests

    call(headers: { 'Authorization' => "Bearer #{other_token}" })
    assert_response :success
  end

  test '不納管的 endpoint 不受 rate limit' do
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 1).times { call }
    assert_response :too_many_requests

    get '/health'
    assert_response :success
  end

  # --- 校內 IP 豁免 ---

  test '校內 IP 超過匿名額度也不會 429' do
    internal!
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 10).times { call(headers: from_internal) }
    assert_response :success
  end

  test '校內 IP 帶 key 也不受 per-user 額度限制' do
    internal!
    (ApiKeyAuthentication::KEYED_LIMIT + 10).times do
      call(headers: from_internal.merge(bearer))
    end
    assert_response :success
  end

  test '校內 IP 的流量不會用掉其他人的額度' do
    internal!
    (ApiKeyAuthentication::ANONYMOUS_LIMIT + 10).times { call(headers: from_internal) }

    call(headers: { 'REMOTE_ADDR' => '198.51.100.7' })
    assert_response :success
  end

  test '額度依 remote_addr 計算,偽造 X-Forwarded-For 繞不過去' do
    # 之前 by: 用的是 remote_ip,它會優先採信 client 送來的 X-Forwarded-For,
    # 於是輪替那個 header 就能無限繞過限流（2026-09-11 於 dev 實測確認）。
    ApiKeyAuthentication::ANONYMOUS_LIMIT.times do
      call(headers: { 'REMOTE_ADDR' => '198.51.100.7' })
    end
    assert_response :success

    call(headers: { 'REMOTE_ADDR' => '198.51.100.7',
                    'HTTP_X_FORWARDED_FOR' => '198.51.100.250' })
    assert_response :too_many_requests
  end

  test 'rate limit 上限低於 fail2ban 的 cbeta-api-r3（約 540 req/min）' do
    # 設計文件 6.2: 把 Rails 上限訂在 fail2ban 之下,429 才會先於「ban 整個
    # IP 一小時」發生。若有人調高這個數字,這個測試要一起檢討。
    fail2ban_effective_limit = 540
    assert ApiKeyAuthentication::KEYED_LIMIT < fail2ban_effective_limit
    assert ApiKeyAuthentication::ANONYMOUS_LIMIT < fail2ban_effective_limit
  end
end
