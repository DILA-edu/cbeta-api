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
    if work == 'T0220'
      file.sub(/[a-z]$/, '') + '_p' + lb
    elsif work.match(/[a-zA-Z]$/)
      file + 'p' + lb
    else
      file + '_p' + lb
    end
  end
  
  def goto_info(args={})
    logger.debug 'goto_info'
    logger.debug __LINE__
    logger.debug args
    r = {}
    r[:vol] = args[:vol].sub /^T(\d)$/, 'T0\1' # T2 => T02
    if args.key? :lb
      r[:lb] = args[:lb]
    elsif not args[:page].nil?
      r[:lb] = lb_from_params args
    end
    canon = CBETA.get_canon_from_vol(r[:vol])
    w = canon + Work.normalize_no(args[:work])
    w = Work.normalize_work(w)
    r[:work] = w
    r[:file] = Work.first_file_in_vol(w, r[:vol])
    r
  end
  
  def goto_linehead(params)
    if params.key? :linehead
      lh = params[:linehead].strip
    else
      lh = params[:linehead_start].strip
    end

    # 行首資訊格式，例：T01n0001_p0066c25, Y01n0001_pa001a01
    if lh.match(/^((?:#{CBETA::CANON})\d{2,3})n(.{5})p([a-z\d]\d{3}[a-z]\d+)$/)
      linehead = lh
      r = goto_info vol: $1, work: $2, lb: $3

    # CBETA 引用格式，例：
    #   * CBETA, T01, no. 1, p. 67, a13
    #   * CBETA 2019.Q2, T01, no. 1, p. 1a6
    elsif lh.match(/^CBETA(?: \d+\.[QR]\d)?, *((?:#{CBETA::CANON})\d{2,3}), *no\. *(.*?), *p\. *([a-z]?\d+), *([a-z])(\d+)(\-.*)?$/)
      r = goto_info vol: $1, work: $2, page: $3, col: $4, line: $5

    # CBETA 2017 新引用格式，例：
    #   CBETA, T30, no. 1579, pp. 279a7-280b26
    #   CBETA, T30, no. 1579, p. 279a7-b23
    #   CBETA, T30, no. 1579, p. 279a7-23
    #   CBETA, T30, no. 1579, p. 279a7
    elsif lh.match(/^CBETA(?: \d+\.[QR]\d)?, ?((?:#{CBETA::CANON})\d+), ?no\. ?([A-Za-z]?\d+[A-Za-z]?), ?pp?\. *([a-z]?\d+)([a-z])(\d+)/)
      r = goto_info vol: $1, work: $2, page: $3, col: $4, line: $5
      logger.debug "Line: #{__LINE__}"
      logger.debug r
  
    # 論文引用慣例，例如：
    #   * 沒有欄號：T51, no. 2087, pp. 868-888
    #   * 沒有行號：T46, no. 1911, p. 18c
    #   * 行號範圍：T15, no. 602, p. 64a14-b26
    #   * 頁碼範圍：T15, no. 606, pp. 215c22-216a2
    elsif lh.match(/^(#{CBETA::CANON}\d+), ?no\. ?([A-Za-z]?\d+[A-Za-z]?), ?pp?\. ?(\d+)([a-z])?(\d+)?/)
      r = goto_info vol: $1, work: $2, page: $3, col: $4, line: $5
    elsif lh.match(/^《大正藏》冊(\d+)，第(\d+[A-Za-z]?) ?號，卷(\d+)/)
      r = goto_by_work canon: 'T', work: $2, juan: $3
    elsif lh.match(/^《大正藏》冊(\d+)，第(\d+[A-Za-z]?) ?號(?:，頁(\d+)([a-z])?(\d+)?)?/)
      # 《大正藏》冊19，第974C 號，頁386
      r = goto_info vol: "T#{$1}", work: $2, page: $3, col: $4, line: $5
    elsif lh.match(/《續藏經》冊(\d+)，頁(\d+)([a-z])?(\d+)?/)
      #《續藏經》冊142，頁1003b
      opts = { vol: $1, page: $2, col: $3, line: $4 }
      opts = r2x opts
      r = goto_by_vol opts
    elsif lh.match(/R(\d+), p\. (\d+)([a-z])?(\d+)?/)
      #R130, p. 861b7
      opts = r2x(vol: $1, page: $2, col: $3, line: $4)
      r = goto_by_vol opts
    elsif lh.match(/^R(\d+)$/)
      opts = r2x(vol: $1)
      r = goto_by_vol opts
    else
      row = GotoAbbr.find_by abbr: lh
      if row.nil?
        return { 
          error: { code: 400, message: "行首資訊格式錯誤：#{lh}" }
        }
      end
      r = goto_linehead linehead: row.ref
    end

    logger.debug "Line: #{__LINE__}"
    logger.debug r
    if r[:juan].nil? and not r[:lb].nil?
      if linehead.nil?
        linehead = get_linehead(r[:work], r[:file], r[:lb])
      end
      line = Line.find_by(linehead: linehead)
      if line.nil?
        return { 
          error: { code: 404, message: "這個行首資訊在 CBETA 裡找不到：#{linehead}" }
        }
      end
      r[:juan] = line.juan
      r[:linehead] = linehead
    end

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
  
  # 將 卍續藏 新文豐 行號 轉為 X 行號
  def r2x(opts)
    lb2 = "R%03d" % opts[:vol].to_i
    
    unless opts[:page].nil?
      lb2 += ".%04d" % opts[:page].to_i
      unless opts[:col].nil?
        lb2 += opts[:col]
        unless opts[:line].nil?
          lb2 += "%02d" % opts[:line].to_i
        end
      end
    end

    row = LbMap.where('lb2 LIKE ?', lb2+'%').first
    if row.nil?
      raise CbetaError.new(404), "新文豐版出處 找不到對應的 卍續藏出處: #{lb2}"
    end

    r = nil
    row.lb1.match /^X(\d+)\.(\d+)([a-z])(\d+)$/ do 
      r = {
        canon: 'X',
        vol: $1,
        page: $2,
        col: $3,
        line: $4
      }
    end
    r
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
