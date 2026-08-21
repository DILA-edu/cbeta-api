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
#      - Origin 命中白名單 → 放行。
#      - Origin 為 nil 或不在白名單 → 過渡期放行,
#        過渡期結束後（config.api_key_required = true）回 401。
#
# | Origin | 帶 key | 過渡期 | 過渡期結束後 |
# |---|---|---|---|
# | 命中白名單   | 無     | 放行 | 放行 |
# | 命中白名單   | 有效   | 放行 | 放行 |
# | 命中白名單   | 無效   | 401  | 401  |
# | nil 或未命中 | 無     | 放行 | 401  |
# | nil 或未命中 | 有效   | 放行 | 放行 |
# | nil 或未命中 | 無效   | 401  | 401  |
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

  included do
    before_action :authenticate_api_key!
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

    return if allowed_origin?
    return allow_without_key if transition_period?

    reject_missing_key
  end

  # 目前這個 request 使用的 key（沒帶 key 就是 nil）
  def current_api_key
    @current_api_key
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
    logger.warn "CBETA API key auth failure from #{request.remote_ip} for #{request.fullpath}"
    render_api_key_error(:unauthorized, 'API key 無效或已撤銷')
  end

  def reject_missing_key
    render_api_key_error(:unauthorized, '本 API 需要 API key。請在 HTTP header 帶 Authorization: Bearer <api_key>')
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
