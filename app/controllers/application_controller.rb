class ApplicationController < ActionController::Base
  before_action :record_visit
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  
  # 因為回傳 json 要有 callback
  #protect_from_forgery with: :exception
  protect_from_forgery only: :create

  def referer_cn?
    request.referer.end_with?('cbetaonline.cn')
  end

  def get_canon_from_work_id(id)
    id.sub(/^(GA|GB|[A-Z]).*$/, '\1')
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
    elsif lh.match(/^CBETA(?: \d+\.Q\d)?, *((?:#{CBETA::CANON})\d{2,3}), *no\. *(.*?), *p\. *([a-z]?\d+), *([a-z])(\d+)(\-.*)?$/)
      r = goto_info vol: $1, work: $2, page: $3, col: $4, line: $5

    # CBETA 2017 新引用格式，例：
    #   CBETA, T30, no. 1579, pp. 279a7-280b26
    #   CBETA, T30, no. 1579, p. 279a7-b23
    #   CBETA, T30, no. 1579, p. 279a7-23
    #   CBETA, T30, no. 1579, p. 279a7
    elsif lh.match(/^CBETA(?: \d+\.Q\d)?, ?((?:#{CBETA::CANON})\d+), ?no\. ?([A-Za-z]?\d+[A-Za-z]?), ?pp?\. *([a-z]?\d+)([a-z])(\d+)/)
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
        if r[:work] == 'T0220'
          linehead = r[:file].sub(/[a-z]$/, '') + '_p' + r[:lb]
        elsif r[:work].match(/[a-zA-Z]$/)
          linehead = r[:file] + 'p' + r[:lb]
        else
          linehead = r[:file] + '_p' + r[:lb]
        end
      end
      line = Line.find_by(linehead: linehead)
      if line.nil?
        return { 
          error: { code: 404, message: "這個行首資訊在 CBETA 裡找不到：#{linehead}" }
        }
      end
      r[:juan] = line.juan
    end
    r
  end
  
  # 將 組字式 轉為 PUA
  def handle_zzs(q)
    return nil if q.nil?
    return q unless q.include? '['
    r = q.gsub(/\[[^\]]+\]/) do |s|
      g = Gaiji.find_by zzs: s
      if g.nil?
        s
      else
        [0xf0000 + g.cb[2..-1].to_i].pack 'U'
      end
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
    unless referer.nil?
      # referer 只記錄 host
      referer = referer.split('//').last.split('/').first
    end

    v = Visit.find_or_create_by(
      url: path, 
      referer: referer,
      accessed_at: Date.today
    )
    v.update(count: v.count + 1)
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
  
  def remove_puncs(s)
    s.gsub(/[\n\.\[\]\(\)\-\*　。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）—]/, '')
  end
  
end
