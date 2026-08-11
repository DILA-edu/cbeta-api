# frozen_string_literal: true

class ApplicationController < ActionController::Base
  rescue_from Rack::Timeout::RequestTimeoutException, with: :handle_request_timeout
  before_action :log_action_start
  before_action :record_visit
  after_action  :log_action_end

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  
  # 因為回傳 json 要有 callback
  skip_before_action :verify_authenticity_token # 整個 Controller 關閉檢查

  EMPTY_RESULT = { num_found: 0, results: [] }

  MAX_QUERY_LENGTH = 80 # 全文檢索 q 參數長度上限（字數）

  def filter_cn?(n: nil, id: nil)
    unless n.nil?
      r = Rails.configuration.cn_filter.join('|')
      return true if n.match?(/^Vol-(#{r})$/)
    end

    unless id.nil?
      # YP 不屏蔽
      if id =~ /^(#{CBETA::CANON})[\d ].*$/
        canon = $1
        return true if Rails.configuration.cn_filter.include?(canon)
      else
        return false
      end
    end
  end

  def referer_cn?
    return true if Rails.env.development? and params[:cn] == "1"
    host = 
      if request.referer
        request.referer.split('//').last.split('/').first
      else
        request.host
      end
    return true if host.end_with?('.cn')
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

  # 解析行首資訊/引用格式，並套用 .cn 站台的過濾
  def goto_linehead(params)
    r = goto_service.linehead(params)

    if referer_cn? and filter_cn?(id: r[:work])
      r = EMPTY_RESULT
    end

    r
  end

  def record_visit
    # 去掉 sub domain
    path = request.path.sub(%r{^/(dev|stable|v1.2)/}, '/')
    if path.start_with?('/download')
      a = path.split('/')
      path = a.first(3).join('/')
    end

    referer = request.referer
    referer = 
      if referer.nil?
        request.remote_ip
      else
        # referer 只記錄 host
        referer.split('//').last.split('/').first
      end
    
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
  end
  
  def my_render(data)
    if data.nil?
      data = {
        num_found: 0,
        results: []
      }
    end

    if params.key? 'callback'
      render json: data, :callback => params['callback'], content_type: "application/javascript"
    else
      render json: data
    end
  end

  def my_render_error(code, message)
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
    logger.debug params.inspect
  end

  def log_debug(msg)
    location = caller_locations.first
    file = File.basename(location.path)
    logger.debug "#{file}:#{location.lineno}, #{msg}"
  end

  def log_info(msg)
    location = caller_locations.first
    file = File.basename(location.path)
    logger.info "#{file}:#{location.lineno}, #{msg}"
  end

  def validate_param_int(k)
    return unless params.key?(k)
    unless params[k] =~ /\A\d+\z/
      raise CbetaError.new(400), "#{k.to_s} 必須是數字"
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

  def handle_request_timeout(e)
    logger.warn(e.class)
    render json: { 
      error: { 
        code: 504, message: "#{e.class} Request timed out." 
      } 
    }, status: :request_timeout
  end
end
