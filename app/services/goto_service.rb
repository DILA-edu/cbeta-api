# frozen_string_literal: true

# 把「行首資訊 / 各種引用格式」解析成 CBETA 位置資訊
# (work, vol, file, juan, lb, linehead)。
#
# 原本散在 ApplicationController 與 JuansController，
# 但這是純 domain logic，與 request 無關,
# rake task、MCP 等非 request 情境也需要，所以抽成 service。
#
# 與 request 相關的處理 (例如 .cn 站台的過濾) 留在 controller。
class GotoService
  # 組出 cbeta 行首資訊字串
  def self.get_linehead(work, file, lb)
    if work == 'T0220'
      file.sub(/[a-z]$/, '') + '_p' + lb
    elsif work.match(/[a-zA-Z]$/)
      file + 'p' + lb
    else
      file + '_p' + lb
    end
  end

  def initialize
    @work_id = nil
    @vol = nil
    @juan = nil
  end

  # params 可以是 Hash 或 ActionController::Parameters
  def linehead(params)
    lh =
      if params.key? :linehead
        params[:linehead].strip
      else
        params[:linehead_start].strip
      end

    lh_exact = nil # 已經是行首資訊格式，不必再組

    # 行首資訊格式，例：T01n0001_p0066c25, Y01n0001_pa001a01
    if lh.match(/^((?:#{CBETA::CANON})\d{2,3})n(.{5})p([a-z\d]\d{3}[a-z]\d+)$/)
      lh_exact = lh
      r = info vol: $1, work: $2, lb: $3

    # CBETA 引用格式，例：
    #   * CBETA, T01, no. 1, p. 67, a13
    #   * CBETA 2019.Q2, T01, no. 1, p. 1a6
    elsif lh.match(/^CBETA(?: \d+\.[QR]\d)?, *((?:#{CBETA::CANON})\d{2,3}), *no\. *(.*?), *p\. *([a-z]?\d+), *([a-z])(\d+)(\-.*)?$/)
      r = info vol: $1, work: $2, page: $3, col: $4, line: $5

    # CBETA 2017 新引用格式，例：
    #   CBETA, T30, no. 1579, pp. 279a7-280b26
    #   CBETA, T30, no. 1579, p. 279a7-b23
    #   CBETA, T30, no. 1579, p. 279a7-23
    #   CBETA, T30, no. 1579, p. 279a7
    elsif lh.match(/^CBETA(?: \d+\.[QR]\d)?, ?((?:#{CBETA::CANON})\d+), ?no\. ?([A-Za-z]?\d+[A-Za-z]?), ?pp?\. *([a-z]?\d+)([a-z])(\d+)/)
      r = info vol: $1, work: $2, page: $3, col: $4, line: $5

    # 論文引用慣例，例如：
    #   * 沒有欄號：T51, no. 2087, pp. 868-888
    #   * 沒有行號：T46, no. 1911, p. 18c
    #   * 行號範圍：T15, no. 602, p. 64a14-b26
    #   * 頁碼範圍：T15, no. 606, pp. 215c22-216a2
    elsif lh.match(/^(#{CBETA::CANON}\d+), ?no\. ?([A-Za-z]?\d+[A-Za-z]?), ?pp?\. ?(\d+)([a-z])?(\d+)?/)
      r = info vol: $1, work: $2, page: $3, col: $4, line: $5
    elsif lh.match(/^《大正藏》冊(\d+)，第(\d+[A-Za-z]?) ?號，卷(\d+)/)
      r = by_work canon: 'T', work: $2, juan: $3
    elsif lh.match(/^《大正藏》冊(\d+)，第(\d+[A-Za-z]?) ?號(?:，頁(\d+)([a-z])?(\d+)?)?/)
      # 《大正藏》冊19，第974C 號，頁386
      r = info vol: "T#{$1}", work: $2, page: $3, col: $4, line: $5
    elsif lh.match(/《續藏經》冊(\d+)，頁(\d+)([a-z])?(\d+)?/)
      #《續藏經》冊142，頁1003b
      opts = { vol: $1, page: $2, col: $3, line: $4 }
      r = by_vol r2x(opts)
    elsif lh.match(/R(\d+), p\. (\d+)([a-z])?(\d+)?/)
      #R130, p. 861b7
      r = by_vol r2x(vol: $1, page: $2, col: $3, line: $4)
    elsif lh.match(/^R(\d+)$/)
      r = by_vol r2x(vol: $1)
    else
      row = GotoAbbr.find_by abbr: lh
      if row.nil?
        return {
          error: { code: 400, message: "行首資訊格式錯誤：#{lh}" }
        }
      end
      return linehead(linehead: row.ref)
    end

    return r if r.key?(:error)

    if r[:juan].nil? and not r[:lb].nil?
      lh_exact ||= self.class.get_linehead(r[:work], r[:file], r[:lb])
      line = Line.find_by(linehead: lh_exact)
      if line.nil?
        return {
          error: { code: 404, message: "這個行首資訊在 CBETA 裡找不到：#{lh_exact}" }
        }
      end
      r[:juan] = line.juan
      r[:linehead] = lh_exact
    end

    r
  end

  # goto 書本結構
  def by_vol(opts)
    canon = opts[:canon]
    @work_id = work_id_from(opts)
    @vol = CBETA.normalize_vol(canon + opts[:vol])

    line = Line.find_by_vol_params(opts)

    if @work_id
      if @work_id != line.work
        return {
          error: { code: 400, message: "Word ID #{@work_id} 與 #{line.linehead} 不符" }
        }
      end
      work = @work_id
    else
      work = line.work
    end

    {
      vol: @vol,
      work: work,
      file: Work.first_file_in_vol(work, @vol),
      juan: line.juan,
      lb: line.page + line.col + line.line,
      linehead: line.linehead
    }
  end

  # goto 經卷結構
  def by_work(params)
    canon = params[:canon]
    @work_id = work_id_from(params)

    work = Work.find_by n: @work_id
    if work.nil?
      return {
        error: { code: 404, message: "Work ID (佛典編號) not found: #{@work_id}" }
      }
    end

    file = work.first_file
    @vol = file.sub(/^(.*?)n.*$/, '\1')

    if params.key? :juan
      @juan = params[:juan].to_i
    else
      @juan = work.juan_start
    end

    if params.key? :page
      unless params.key?(:vol)
        params[:vol] = @vol.delete_prefix(canon).to_i.to_s
      end
      line = Line.find_by_vol_params(params)
      @juan = line.juan unless params.key?(:juan)
    else
      line = Line.find_by(work: @work_id, juan: @juan)
      if line.nil?
        s = "Line record 不存在: work: #{@work_id}, juan: #{@juan}"
        raise CbetaError.new(404), s
      end
      @vol = line.vol
    end

    {
      vol: @vol,
      work: @work_id,
      file: ,
      juan: @juan,
      lb: line.page + line.col + line.line,
      linehead: line.linehead
    }
  end

  private

  # 呼叫端指定的佛典編號，例: canon "T" + work "1" => "T0001"
  # 沒指定 work 就回 nil，表示不比對。
  def work_id_from(params)
    return nil unless params[:canon] and params[:work]
    # normalize_no 會 chomp! 傳入的字串，所以給它副本
    params[:canon] + Work.normalize_no(params[:work].to_s.dup)
  end

  def info(args = {})
    logger.debug 'GotoService#info'
    logger.debug args
    r = {}
    r[:vol] = args[:vol].sub(/^T(\d)$/, 'T0\1') # T2 => T02
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

  def lb_from_params(params)
    logger.debug "GotoService#lb_from_params, page: #{params[:page]}"

    page = params[:page]
    if page.match(/^([a-z])(\d+)$/)
      page = $1 + $2.rjust(3, '0')
    elsif page.match(/^\d+$/)
      page = page.rjust(4, '0')
    else
      raise CbetaError.new(400), "頁碼格式錯誤：#{params[:page]}"
    end

    if @work_id.nil? or @juan.nil?
    else
      vol, start_lb = JuanLine.get_first_lb_by_work_juan(@work_id, @juan)
      start_page = start_lb.sub(/^(\d{4}).*$/, '\1')
      if page < start_page
        raise CbetaError.new(400), "頁碼小於起始頁碼, 佛典編號: #{@work_id}, 卷號: #{@juan}, 起始頁碼: #{start_lb}, 要求頁碼: #{page}"
      end
    end

    lb = page
    if params[:col].nil?
      lb += 'a01'
    else
      col = params[:col]
      unless col.match(/^[a-z]$/)
        raise CbetaError.new(400), "欄號格式錯誤: #{col}"
      end
      lb += col
      if params[:line].nil?
        lb += '01'
        if not params.key?(:vol) or params[:vol] == vol
          lb = start_lb if lb < start_lb
        end
      else
        line = params[:line]
        unless line.match(/^\d+$/)
          raise CbetaError.new(400), "行號格式錯誤: #{line}"
        end
        lb += line.rjust(2, '0')
      end
    end
    logger.debug "GotoService#lb_from_params, lb: #{lb}"

    unless @vol.nil? or @work_id.nil?
      juan = JuanLine.get_juan_by_vol_work_lb(@vol, @work_id, lb)
      if juan.nil?
        raise CbetaError.new(400), "冊號、典籍編號、行號 不符: vol: #{@vol}, work: #{@work_id}, lb: #{lb}"
      end
    end

    lb
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

    row = LbMap.where('lb2 LIKE ?', lb2 + '%').first
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

  def logger
    Rails.logger
  end
end
