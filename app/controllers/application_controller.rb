# frozen_string_literal: true

class ApplicationController < ActionController::Base
  rescue_from Rack::Timeout::RequestTimeoutException, with: :handle_request_timeout

  # CbetaError 帶著自己的 HTTP status code, 但先前沒有 handler, 未被 method 內的
  # begin/rescue 接住的就一律變成 500。
  # 註: SearchController 自己註冊了 rescue_from Exception, 子類別的 handler 優先,
  #     所以它的行為不受這裡影響。method 內的 rescue CbetaError 也一樣優先。
  rescue_from CbetaError, with: :handle_cbeta_error
  before_action :log_action_start
  before_action :record_visit
  before_action :record_origin
  after_action  :log_action_end

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  
  # 因為回傳 json 要有 callback
  skip_before_action :verify_authenticity_token # 整個 Controller 關閉檢查

  EMPTY_RESULT = { num_found: 0, results: [] }

  MAX_QUERY_LENGTH = 40 # 全文檢索 q 參數長度上限（字數）

  # 斷詞、簡轉繁每個 request 都 spawn 外部程式，處理時間與長度成正比
  # (staging 斷詞約每千字 0.15 秒)。上限足以涵蓋一整卷經文，擋住超大輸入佔住 worker。
  MAX_TOOL_INPUT_LENGTH = 50_000

  def tool_input_too_long?(text)
    text.to_s.size > MAX_TOOL_INPUT_LENGTH
  end

  def tool_input_length_error(name)
    "#{name} 參數長度不得大於 #{MAX_TOOL_INPUT_LENGTH} 字"
  end

  # JSONP 的 callback 會被寫進 JS 回應,只允許合法的 JS identifier
  # （含 dotted path,例如 window.foo）
  SAFE_CALLBACK = /\A[A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)*\z/

  # Referer 的 host (含 port)。沒有 Referer 或解析不出 host
  # (例如空字串、"/") 時回傳 nil。
  def referer_host
    ref = request.referer
    return nil if ref.blank?

    ref.split('//').last&.split('/')&.first.presence
  end

  # 通過驗證的 JSONP callback 名稱; 沒帶或不合法時回傳 nil (改回傳一般 JSON)
  def jsonp_callback
    callback = params[:callback]
    callback if callback.is_a?(String) && callback.match?(SAFE_CALLBACK)
  end

  def get_canon_from_work_id(id)
    id.sub(/^(GA|GB|[A-Z]).*$/, '\1')
  end

  def get_linehead(work, file, lb)
    GotoService.get_linehead(work, file, lb)
  end

  def goto_service
    @goto_service ||= GotoService.new
  end

  # 解析行首資訊/引用格式
  def goto_linehead(params)
    goto_service.linehead(params)
  end

  def record_visit
    # 去掉 sub domain
    path = request.path.sub(%r{^/(dev|stable|v1.2)/}, '/')
    if path.start_with?('/download')
      a = path.split('/')
      path = a.first(3).join('/')
    end

    # referer 只記錄 host; 沒有 referer 時記錄 IP
    referer = referer_host || request.remote_ip

    sql = <<~SQL
      INSERT INTO visits (url, referer, accessed_at, count)
      VALUES (?, ?, ?, 1)
      ON CONFLICT (url, referer, accessed_at)
      DO UPDATE SET count = visits.count + 1
    SQL

    Visit.connection.execute(
      Visit.sanitize_sql_array(
        [sql, path, referer, Date.today]
      )
    )
  rescue StandardError => e
    # 統計不該讓 API 呼叫失敗 (同 record_origin)
    logger.warn "記錄 visits 失敗: #{e.class}: #{e.message}"
  end
  
  # 過渡期埋點: 記錄每個 Origin 每天的 request 數。
  #
  # 用途是在過渡期結束前確認 cbetaonline 的流量落在「命中白名單」還是
  # 「Origin 為 nil」—— 若全部落在 nil,過渡期一結束前端就會全站掛掉,
  # 必須提前發現,不能等前端工程師回覆。
  #
  # 埋點不該讓 API 呼叫失敗,因此吞掉例外只寫 log。
  #
  # 見 doc/api-key-design.md 4.5
  def record_origin
    OriginStat.record!(request.origin)
  rescue StandardError => e
    logger.warn "記錄 Origin 統計失敗: #{e.class}: #{e.message}"
  end

  def my_render(data)
    if data.nil?
      data = {
        num_found: 0,
        results: []
      }
    end
    @error_response = true if data.is_a?(Hash) && (data.key?(:error) || data.key?('error'))

    if (callback = jsonp_callback)
      render json: data, callback:, content_type: "application/javascript"
    else
      render json: data
    end
  end

  def my_render_error(code, message)
    @error_response = true
    r = { 
      error: { code: , message: } 
    }
    render json: r
  end
  
  def log_action_end
    logger.debug "end #{controller_name}##{action_name} #{@start_time}, spend_time: #{Time.now-@start_time}"
  end

  def log_action_start
    @start_time = Time.now
    user_agent = UserAgent.parse(request.user_agent)
    
    # warn level log for fail2ban
    msg = +"Request #{request.fullpath} from #{request.remote_ip} at #{@start_time}"
    msg << ", referer: #{request.referer}, origin: #{request.origin}"
    msg << ", user_agent: #{user_agent.platform}/#{user_agent.browser}/#{user_agent.version}"
    logger.warn msg

    logger.debug "start #{controller_name}##{action_name} #{@start_time}"
    # 經 filter_parameters 過濾; block 形式在 log level 非 debug 時不組字串
    logger.debug { request.filtered_parameters.inspect }
  end

  def log_debug(msg)
    # log level 不是 debug 時, 省下擷取 call stack 的成本
    return unless logger.debug?

    location = caller_locations(1, 1).first
    file = File.basename(location.path)
    logger.debug "#{file}:#{location.lineno}, #{msg}"
  end

  def log_info(msg)
    location = caller_locations(1, 1).first
    file = File.basename(location.path)
    logger.info "#{file}:#{location.lineno}, #{msg}"
  end

  def validate_param_int(k)
    return unless params.key?(k)
    unless params[k] =~ /\A\d+\z/
      raise CbetaError.new(400), "#{k} 必須是數字"
    end
  end

  # 全文檢索 q 參數是否超過長度上限（字數）
  def query_too_long?(q)
    q.to_s.size > MAX_QUERY_LENGTH
  end

  # q 超過長度上限時統一使用的錯誤訊息
  def query_length_error
    "q 參數長度不得大於 #{MAX_QUERY_LENGTH} 字"
  end

  private

  # 內容只隨資料版本 (季號 cb.r) 與程式版號改變的端點，以 ETag 支援條件式請求。
  #
  # 回應裡的 time 欄位每次都不同，Rack::ETag 依內容算出的 ETag 永遠對不上，
  # 所以由這裡依「資料版本 + 程式版號 + 完整網址 (+ extra)」指定。
  # 內容沒變時回 304，省下產生與傳送內容。
  #
  # 不設 max-age: 瀏覽器每次仍會回來驗證，visits、api key 用量等統計照常記錄。
  # 錯誤回應不帶 ETag (有些錯誤以 HTTP 200 回傳)，以免暫時性的錯誤被快取住。
  #
  # extra: 季中可能更新、但季號不變的來源，例如資料檔的修改時間。
  def with_release_etag(*extra)
    response.etag = [ Rails.configuration.cb.r, Rails.configuration.x.ver, request.fullpath, *extra ]
    # 304 只用於 GET / HEAD (HTTP 規範); 這些端點也接受 POST, POST 一律回傳完整內容
    return head(:not_modified) if (request.get? || request.head?) && request.fresh?(response)

    yield
    response.delete_header('ETag') if @error_response || !response.successful?
  rescue Exception # rubocop:disable Lint/RescueException -- 只為了拿掉 ETag, 原樣再丟出
    response.delete_header('ETag')
    raise
  end

  # with_release_etag 的 extra: 檔案的修改時間與大小 (不存在時為 nil)
  def file_stamp(path)
    st = File.stat(path)
    [ st.mtime.to_i, st.size ]
  rescue Errno::ENOENT
    nil
  end

  # 回傳給 client 的錯誤訊息。不回傳 backtrace（會洩漏伺服器路徑），完整錯誤寫進 log。
  # CbetaError 的訊息是寫給使用者看的，但部分訊息含檔案路徑，去掉 Rails.root 前綴；
  # 其他例外的訊息是內部細節，一律不對外。
  def public_error_message(e)
    if e.is_a?(CbetaError) && e.code.to_i.between?(400, 499)
      logger.warn "CbetaError(#{e.code}): #{e.message}"
    else
      logger.error "#{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
    end
    return '伺服器內部錯誤' unless e.is_a?(CbetaError)

    e.message.gsub("#{Rails.root}/", '')
  end

  # Asia Network API (/api/*) 的 uuid 查無資料
  def render_asia_not_found(uuid)
    render json: { error: { code: 404, message: "uuid 不存在: #{uuid}" } }, status: :not_found
  end

  def handle_cbeta_error(e)
    code = e.code.is_a?(Integer) && e.code.between?(400, 599) ? e.code : 500
    logger.warn "CbetaError(#{code}): #{e.message}"

    r = { error: { code:, message: e.message } }
    if (callback = jsonp_callback)
      render json: r, callback:, content_type: 'application/javascript', status: code
    else
      render json: r, status: code
    end
  end

  # 回 504 而不是 408: 408 表示 client 送 request 太慢, 部分 client 會自動重送,
  # 等於把逾時的重查詢再跑一次。
  def handle_request_timeout(e)
    logger.warn(e.class)
    render json: {
      error: {
        code: 504, message: "#{e.class} Request timed out."
      }
    }, status: :gateway_timeout
  end
end
