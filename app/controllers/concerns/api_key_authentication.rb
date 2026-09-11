# frozen_string_literal: true

# API key 驗證。
#
# 採 allowlist —— 由需要納管的 controller 明確 include。漏掉的後果是「該
# endpoint 沒納管」,而不是「意外擋掉不該擋的東西」,語意比 denylist 安全。
#
# 判斷順序（過渡期）:
#
#   1. 有帶 Authorization: Bearer → 一律驗證。key 無效即回 401,
#      即使 Origin 命中白名單也一樣。
#      理由: 帶了無效 key 通常是 client 設定錯誤。靜默放行會讓開發者誤以為
#      key 有效,等過渡期結束才一次爆掉。
#   2. 未帶 key:
#      - 校內 IP（config.api_internal_ip_ranges）→ 放行,且不套 rate limit。
#      - Origin 命中白名單 → 放行。
#      - Origin 為 nil 或不在白名單 → 過渡期放行,
#        過渡期結束後（config.api_key_required = true）回 401。
#
# | 來源 | 帶 key | 過渡期 | 過渡期結束後 |
# |---|---|---|---|
# | 校內 IP      | 無     | 放行 | 放行 |
# | 校內 IP      | 有效   | 放行 | 放行 |
# | 校內 IP      | 無效   | 401  | 401  |
# | 命中白名單   | 無     | 放行 | 放行 |
# | 命中白名單   | 有效   | 放行 | 放行 |
# | 命中白名單   | 無效   | 401  | 401  |
# | nil 或未命中 | 無     | 放行 | 401  |
# | nil 或未命中 | 有效   | 放行 | 放行 |
# | nil 或未命中 | 無效   | 401  | 401  |
#
# rate limit: 校內 IP 完全豁免; 其餘未帶 key 60/min/IP、帶 key 300/min/user。
# 校內 IP 範圍放 config/cb.yml（不進版控）,且刻意不寫進對外公開的說明頁。
#
# 只接受 HTTP header,不接受 query param（如 ?api_key=）—— query string 會被
# 寫入 Apache access log、Rails log 與 visits 統計,等於在多處留下明文 key。
#
# 見 doc/api-key-design.md 3
module ApiKeyAuthentication
  extend ActiveSupport::Concern

  REALM = 'CBETA API'

  # 過渡期未帶 key 而放行時加上這個 header,讓 client 開發者能提早發現。
  # 這比只在網站公告有效。
  HINT_HEADER = 'X-CBETA-API-Key'

  # JSONP 的 callback 會被寫進 JS 回應,只允許合法的 JS identifier
  # （含 dotted path,例如 window.foo）
  SAFE_CALLBACK = /\A[A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)*\z/

  # --- rate limit（見設計文件 6）---
  #
  # 「api key 控管」若沒有配額,key 只是身分標籤。且過渡期「未帶 key 就放行」
  # 意味著防護等於零: 濫用者只要不帶 key 就完全不受限,正常使用者反而要多做事,
  # 沒有任何動機申請 key。因此帶 key 享有明顯較高的額度。
  RATE_LIMIT_WINDOW = 1.minute
  ANONYMOUS_LIMIT = 60  # per IP
  KEYED_LIMIT = 300     # per user

  # Rails 的 rate_limit 在 include 時就把 store 收進 closure,無法在
  # runtime 替換。這層薄殼把它延後到 request 時才解析 Rails.cache,
  # 好處是測試能換成 MemoryStore 實測 429
  # （test 環境的 cache_store 是 null_store,increment 回 nil，
  #  rate limit 形同停用，否則整個測試套件都會受 60/min 的限制影響）。
  RATE_LIMIT_STORE = Object.new
  def RATE_LIMIT_STORE.increment(name, amount = 1, **options)
    Rails.cache.increment(name, amount, **options)
  end

  included do
    before_action :authenticate_api_key!

    # rate limit 宣告在 authenticate_api_key! 之後,才能用 current_api_key
    # 判斷該套哪一個額度。
    #
    # scope 明確指定,讓額度跨 controller 共用 —— 預設的 scope 是
    # controller_path,那會變成「每個 controller 各有 60/min」,
    # 等於總額度乘以 controller 數量。
    #
    # 額度設計與 fail2ban 的分工見設計文件 6.2: cbeta-api-r3 jail 的實際上限
    # 約 540 req/min 且懲罰是 ban 整個 IP 一小時,所以 Rails 的 per-user 上限
    # 訂在它之下 (300),429 會先發生,fail2ban 退居最後一道防線。
    #
    # by: 用 remote_addr 而不是 remote_ip —— remote_ip 會優先採信 client 送來的
    # X-Forwarded-For。本站是 Apache + Passenger 直接對外,前面沒有反向 proxy,
    # 所以那個 header 一定是偽造的; 用它當額度 key 等於讓人輪替 header 就能
    # 無限繞過限流(2026-09-11 於 dev 實測確認可繞過)。
    # remote_addr 是 TCP 連線的對端,偽造不了。
    rate_limit to: ANONYMOUS_LIMIT, within: RATE_LIMIT_WINDOW,
               by: -> { request.remote_addr },
               with: -> { reject_rate_limited },
               store: RATE_LIMIT_STORE,
               scope: 'cbeta-api-anonymous',
               unless: -> { api_key_used? || internal_ip? }

    rate_limit to: KEYED_LIMIT, within: RATE_LIMIT_WINDOW,
               by: -> { "user-#{current_api_key.user_id}" },
               with: -> { reject_rate_limited },
               store: RATE_LIMIT_STORE,
               scope: 'cbeta-api-user',
               if: -> { api_key_used? && !internal_ip? }
  end

  private

  def authenticate_api_key!
    token = bearer_token

    if token.present?
      @current_api_key = ApiKey.authenticate(token)
      return reject_invalid_key if @current_api_key.nil?

      record_api_key_use
      return
    end

    # 校內 IP 免 key(也不套 rate limit,見上面 rate_limit 的條件)。
    # 放在 transition_period? 之前,過渡期結束後校內仍然免 key。
    #
    # 位置在 token 分支之後: 帶了無效 key 一律 401,校內也一樣 —— 那通常是
    # client 設定錯誤,靜默放行會讓人誤以為 key 有效。
    return if internal_ip?

    return if allowed_origin?
    return allow_without_key if transition_period?

    reject_missing_key
  end

  # 目前這個 request 使用的 key（沒帶 key 就是 nil）
  def current_api_key
    @current_api_key
  end

  def api_key_used?
    current_api_key.present?
  end

  def bearer_token
    header = request.authorization
    return nil if header.blank?

    header[/\ABearer\s+(.+)\z/i, 1]&.strip
  end

  def allowed_origin?
    origin = request.origin
    return false if origin.blank?

    origin_allowlist.include?(origin)
  end

  # 校內 IP 判斷。用 remote_addr(TCP 對端)而非 remote_ip,理由同上面 rate_limit。
  #
  # ⚠️ 前提是「Apache + Passenger 直接對外」。哪天前面放了 CDN 或 load balancer,
  # remote_addr 會變成那台機器的 IP,這裡必須改寫。
  def internal_ip?
    return @internal_ip if defined?(@internal_ip)

    @internal_ip = internal_ip_ranges.any? { |range| range.include?(client_addr) }
  end

  def client_addr
    IPAddr.new(request.remote_addr.to_s)
  rescue IPAddr::Error
    IPAddr.new('0.0.0.0') # 解析不出來就當成外部
  end

  def internal_ip_ranges
    Rails.configuration.api_internal_ip_ranges
  end

  # 比對只比 Origin 完整字串（scheme + host [+ port]）,不做 subdomain 模糊比對。
  def origin_allowlist
    Rails.configuration.api_origin_allowlist
  end

  def transition_period?
    !Rails.configuration.api_key_required
  end

  def allow_without_key
    response.headers[HINT_HEADER] = 'recommended'
  end

  def record_api_key_use
    @current_api_key.touch_last_used!
    ApiKeyUsage.record!(@current_api_key)
  rescue StandardError => e
    # 統計失敗不該讓 API 呼叫失敗
    logger.warn "記錄 API key 使用量失敗: #{e.class}: #{e.message}"
  end

  def reject_invalid_key
    # 固定格式的 warn log,供日後新增 fail2ban filter 使用（設計文件 6.5）
    # 用 remote_addr: 這行是給 fail2ban 抓的,若寫入可被偽造的 remote_ip,
    # 攻擊者就能讓 fail2ban 去 ban 無辜的第三方 IP。
    logger.warn "CBETA API key auth failure from #{request.remote_addr} for #{request.fullpath}"
    render_api_key_error(:unauthorized, 'API key 無效或已撤銷')
  end

  def reject_missing_key
    render_api_key_error(:unauthorized, '本 API 需要 API key。請在 HTTP header 帶 Authorization: Bearer <api_key>')
  end

  def reject_rate_limited
    limit = api_key_used? ? KEYED_LIMIT : ANONYMOUS_LIMIT
    retry_after = RATE_LIMIT_WINDOW.to_i

    # 讓 client 知道要退讓多久（fail2ban 的懲罰是直接 ban IP 一小時,
    # 429 + Retry-After 溫和得多,所以要讓 429 先發生）
    response.headers['Retry-After'] = retry_after.to_s

    message = "超過流量限制（每分鐘 #{limit} 次）。請於 #{retry_after} 秒後重試"
    message += '。帶有效的 API key 可享有較高額度' unless api_key_used?

    render_api_key_error(:too_many_requests, message)
  end

  # 不走 ApplicationController#my_render_error —— 那個 method 沒有帶 HTTP
  # status（回 200）,而且不能改它的行為（會影響既有 client）。
  #
  # JSONP 的 client 讀不到 HTTP status,錯誤回應仍需支援 callback 包裝。
  def render_api_key_error(status, message)
    code = Rack::Utils.status_code(status)
    body = { error: { code:, message: } }

    response.headers['WWW-Authenticate'] = %(Bearer realm="#{REALM}") if status == :unauthorized

    callback = params[:callback]
    if callback.present? && callback.match?(SAFE_CALLBACK)
      render json: body, callback:, content_type: 'application/javascript', status:
    else
      render json: body, status:
    end
  end
end
