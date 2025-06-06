class Kwic3Controller < ApplicationController
  before_action :init
  
  def init
    return unless params.key?(:q)
    logger.info "#{File.basename(__FILE__)}, line: #{__LINE__}, kwic q: #{params[:q]}"

    raise CbetaError.new(400), "缺少 q 參數" if params[:q].blank?
    @q = Gaiji.replace_zzs_with_pua(params[:q])

    # NEAR/7 語法，允許 數字
    # 允許半形逗點，例： 法鼓,聖嚴
    @q = CbetaString.new(allow_digit: true, allow_comma: true).remove_puncs(@q)

    @q.gsub!(/\\(['"\-\\])/, '\1') # unescape: \' 取代為 ', \" 取代為 "
    logger.info "#{File.basename(__FILE__)}, line: #{__LINE__}, kwic q: #{@q}"
    
    @opts = { 
      inline_note: true,
      referer_cn: referer_cn?
    }
    
    a = %w(sort negative_lookahead negative_lookbehind)
    a.each {|s| @opts[s.to_sym] = params[s] if params.key? s }
    
    a = %w(around juan rows start word_count)
    a.each {|s| @opts[s.to_sym] = params[s].to_i if params.key? s }
    
    @opts[:inline_note]  = false if params['note']         == '0'
    @opts[:place]        = true  if params['place']        == '1'
    @opts[:kwic_w_punc]  = false if params['kwic_w_punc']  == '0'
    @opts[:kwic_wo_punc] = true  if params['kwic_wo_punc'] == '1'
    @opts[:mark]         = true  if params['mark']         == '1'
    @opts[:seg]          = true  if params['seg']          == '1'

    base = Rails.configuration.x.kwic.base
    @se = KwicService.new(base, @opts[:inline_note])
    
    # 檢查 佛典編號 是否存在
    if params.key?('work')
      n = params['work']
      w = Work.find_by n: n
      if w.nil?
        r = { success: false, num_found: 0, results: [], error: '佛典編號不存在'}
        my_render r
        return
      else
        @opts[:work] = n
      end
    end
  end
  
  def juan
    return unless juan_check_params

    t1 = Time.now
    logger.info "#{File.basename(__FILE__)}, line: #{__LINE__}, kwic q: #{@q}"
    if @q.match?(/ NEAR\/(\d+) /)
      logger.debug "search near"
      h = @se.search_near(@q, @opts)
    else
      logger.debug "search juan"
      h = @se.search_juan(@q, @opts)
    end

    num_found = h[:num_found]
    a = h[:results]

    a.each do |h|
      # 卷可能跨冊號，必須保留冊號
      h.delete('work')
      h.delete('juan')
      h.delete('offset_in_text_with_punc')
    end

    r = { num_found: num_found, time: Time.now-t1, results: a}
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
      r = { success: false, error: '缺少必要參數： work 佛典編號'}
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

end
