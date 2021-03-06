class Kwic3Controller < ApplicationController
  around_action :log_action_time
  
  def init
    return unless params.key?(:q)

    base = Rails.root.join('data', 'kwic25')
    @se = Kwic3Helper::SearchEngine.new(base)

    raise CbetaError.new(400), "缺少 q 參數" if params[:q].blank?
    @q = handle_zzs(params[:q])
    @q = remove_puncs(@q)
    
    @opts = {}
    
    a = %w(category canon sort works negative_lookahead negative_lookbehind)
    a.each {|s| @opts[s.to_sym] = params[s] if params.key? s }
    
    a = %w(around juan rows start)
    a.each {|s| @opts[s.to_sym] = params[s].to_i if params.key? s }
    
    @opts[:place]        = true  if params['place']         == '1'
    @opts[:word_count]   = true  if params['word_count']    == '1'
    @opts[:kwic_w_punc]  = false if params['kwic_w_punc']   == '0'
    @opts[:kwic_wo_punc] = true  if params['kwic_wo_punc']  == '1'
    @opts[:mark]         = true  if params['mark']          == '1'
    @opts[:seg]          = true  if params['seg']           == '1'
    
    # 檢查 典籍編號 是否存在
    if params.key?('work')
      n = params['work']
      w = Work.find_by n: n
      if w.nil?
        r = { success: false, num_found: 0, results: [], error: '典籍編號不存在'}
        my_render r
        return
      else
        @opts[:work] = n
      end
    end
  end
  
  def index
    if @q.match(/^"(\S+)" NEAR\/(\d+) "(\S+)"/)
      result = @se.search_near($1, $3, $2.to_i, @opts)
    else
      result = @se.search(@q, @opts)
    end
    my_render result
  rescue CbetaError => e
    r = { 
      num_found: 0,
      error: { code: e.code, message: $!, backtrace: e.backtrace }
    }
    my_render(r)
  end

  def juan
    return unless juan_check_params

    if @q.match(/^"(\S+)" NEAR\/(\d+) "(\S+)"/)
      h = @se.search_near($1, $3, $2.to_i, @opts)
    else
      h = @se.search_juan(@q, @opts)
    end

    num_found = h[:num_found]
    a = h[:results]

    a.each do |h|
      h.delete('vol')
      h.delete('work')
      h.delete('juan')
    end

    r = { num_found: num_found, results: a}
    pp r

    my_render r
  rescue Exception => e
    logger.debug $!
    e.backtrace.each { |s| logger.debug s }
    r = { 
      num_found: 0,
      params: params,
      error: e.message + "\n" + e.backtrace.join("\n")
    }
    my_render r
  end
  
  def extended
    t1 = Time.now
    
    #@opts[:rows] = 0 unless @opts.key? :rows
    
    q = params[:q]
    q.sub!(/\-\s+\S+/, '')
    q.sub!(/[&|]/, '')
    q.sub!(/~\d+/, '')
    
    keywords = q.split(/[ "]+/)
    keywords.shift if keywords.first.empty?
    
    hits = {}
    keywords.each do |k|
      @se.search(k, @opts)[:results].each do |row|
        hits[row['lb']] = row
      end
    end
    
    results = []
    hits.keys.sort.each do |k|
      results << hits[k]
    end
    
    r = {
      query_string: keywords.join(' '),
      time: Time.now - t1,
      total_term_hits: results.size,
      results: results
    }
    
    my_render r
  end

  private

  def juan_check_params
    unless params.key?('work')
      r = { success: false, error: '缺少必要參數： work 典籍編號'}
      my_render r
      return false
    end
    unless params.key?('juan')
      r = { success: false, error: '缺少必要參數： juan 卷號'}
      my_render r
      return false
    end
    unless params.key?('q')
      r = { success: false, error: '缺少必要參數： q 關鍵字'}
      my_render r
      return false
    end
    true
  end

  def log_action_time
    logger.warn("開始處理 " + CGI.unescape(request.url))
    init
    yield
    logger.warn("結束處理 " + CGI.unescape(request.url))
  end
  
end
