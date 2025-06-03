# all_in_one
#   Exclude X -Y
#     1. 先呼叫 Sphinx 取得全部符合 X 的卷數
#     2. 每一卷呼叫 KWIC 過濾 -Y
#        2.1 取得本卷符合 X 的位置
#        2.2 讀取前後文，過濾 -Y
#     3. 計算總筆數、Facet

require 'csv'
require 'open3'

class SearchController < ApplicationController
  RANKER = 'wordcount' # ranking by the keyword occurrences count.
  FACET_MAX = 10_000 # facet 筆數上限, 影響記憶體用量、效率, 參考 2021 佛典數量 5,617
  MAX_MATCHES = 99_999
  SIMILAR_K = 500
  SCORE_MIN = 16

  before_action :init
  after_action  :action_ending
  rescue_from Exception, with: :error_handler

  def initialize
    log_info "SearchController initialize"
  end
  
  # 2019-11-01 決定不以「經」做 group, 因為不能以「經」的 term_hits 做排序
  def all_in_one
    logger.debug Time.now
    @mode = 'extend' # 允許 boolean search
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end

    t1 = Time.now
    r = if @use_cache
          key = "#{Rails.configuration.cb.r}/#{params}-#{@referer_cn}"
          Rails.cache.fetch(key) do
            all_in_one_sub
          end
        else
          all_in_one_sub
        end
    
    r[:cache_key] = key unless key.nil?
    r[:time] = Time.now - t1
    
    my_render r
  end

  def index
    remove_puncs_from_query
    
    if @q.empty?
      my_render(empty_result)
      return
    end
    
    where = %{MATCH('@#{@text_field} "#{@q}"')} + @filter
    @max_matches = MAX_MATCHES
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    my_render r
  end

  def similar
    t1 = Time.now

    key = "#{Rails.configuration.cb.r}/search/similar/#{params}-#{@referer_cn}"

    r = if @use_cache
          Rails.cache.fetch(key) do
            similar_sub
          end
        else
          similar_sub
        end

    r[:cache_key] = key
    r[:time] = Time.now - t1
    my_render r
  end

  def test
    remove_puncs_from_query
    
    if @q.empty?
      my_render(empty_result)
      return
    end
    
    where = %{MATCH('@#{@text_field} "#{@q}"')} + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    my_render r
  end  

  def extended
    @mode = 'extend'
    remove_puncs_from_query
    
    if @q.empty?
      my_render(empty_result)
      return
    end
    
    where = %{MATCH('@#{@text_field} "#{@q}"')} + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    my_render r
  end

  def notes
    log_debug "action notes"
    @mode = 'extend'
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end
    
    @where = "MATCH('#{@q}')" + @filter
    estimate_max_matches
    r = sphinx_search(@fields, @where, @start, @rows, order: @order)

    if params[:facet] == '1'
      r['facet'] = {}
      h = r['facet']
      h['category'] = facet_by_sphinx('category')
      h['creator']  = facet_by_sphinx('creator')
      h['dynasty']  = facet_by_sphinx('dynasty')
      h['work']     = facet_by_sphinx('work')
      h['canon']    = facet_by_sphinx('canon')
    end

    notes_highlight(r)
    my_render r
  ensure
    @mysql_client.close unless @mysql_client.nil?
  end

  def facet
    @mode = 'extend'
    remove_puncs_from_query

    raise CbetaError.new(400), "缺少 q 參數" if @q.empty?

    @where = %{MATCH('@#{@text_field} "#{@q}"')} + @filter
    
    if params.key? :facet_by
      r = facet_by_sphinx(params[:facet_by])
    else
      r = {}
      r['canon']    = facet_by_sphinx('canon')
      r['category'] = facet_by_sphinx('category')
      r['creator']  = facet_by_sphinx('creator')
      r['dynasty']  = facet_by_sphinx('dynasty')
      r['work']     = facet_by_sphinx('work')
    end
            
    my_render r
  ensure
    @mysql_client.close unless @mysql_client.nil?
  end
  
  def fuzzy
    remove_puncs_from_query
    
    if @q.empty?
      my_render(empty_result)
      return
    end
    
    where = "MATCH('@#{@text_field} #{@q}')" + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    my_render r
  ensure
    @mysql_client.close
  end

  # 根據異體字表，回傳各種可能異體字串及搜尋結果筆數
  # 效率測試：
  #   * 無上正等正覺
  #   * 大比丘三千威儀
  #   * 阿耨多羅三藐三菩提
  def variants
    t1 = Time.now

    r = if @use_cache
          key = "#{Rails.configuration.cb.r}/#{params}-#{@referer_cn}"
          Rails.cache.fetch(key) do
            variants_sub
          end
        else
          variants_sub
        end

    r[:cache_key] = key unless key.nil?
    r[:time] = Time.now - t1

    my_render r
  end

  # 以簡體字查詢
  def sc
    raise CbetaError.new(400), "q 參數長度不得大於 50" if params[:q].size > 50

    t1 = Time.now

    # 簡轉繁
    cmd = 'opencc -c s2tw'
    @q, status = Open3.capture2(cmd, stdin_data: params[:q])

    r = if @q == params[:q]
        { q: @q, hits: 0}
      else
        where = %{MATCH('@#{@text_field} "#{@q}"')} + @filter
        i = get_hit_count(where)
        
        r = {
          time: Time.now - t1,
          q: @q,
          hits: i
        }
      end
    my_render r
  ensure
    @mysql_client.close unless @mysql_client.nil?
  end

  # 根據同義詞表，回傳各種可能字串及搜尋結果筆數
  def synonym
    t1 = Time.now
    
    term = Term.find_by term: @q
    if term.nil?
      r = {
        time: Time.now - t1,
        num_found: 0,
        results: []
      }
    else
      results = term.synonyms.split("\t")
      r = {
        time: Time.now - t1,
        num_found: results.size,
        results: results
      }
    end
    my_render r
  end

  # 搜尋 title
  def title
    if @q.empty?
      my_render(empty_result)
      return
    end

    t1 = Time.now
    @index = Rails.configuration.x.se.index_titles
    s = @q.chars.join(' ')
    @where = %{MATCH('"#{s}"/3')} + @filter # /3 表示 至少要有2個字符合
    @max_matches = MAX_MATCHES

    select = <<~SQL
      SELECT work, content
       FROM #{@index}
       WHERE #{@where} 
       LIMIT #{@start}, #{@rows} 
       OPTION max_matches=#{@max_matches}
    SQL

    log_info select
    results = @mysql_client.query(select, symbolize_keys: true)    

    hits = results.to_a
    hits.each do |h|
      h[:highlight] = mark_title(h[:content], @q)
      w = Work.find_by(n: h[:work])
      h[:byline] = w.byline
      h[:juan] = w.juan
      h[:creators_with_id] = w.creators_with_id
      h[:time_dynasty] = w.time_dynasty
      h[:time_from] = w.time_from
      h[:time_to] = w.time_to
    end

    results = @mysql_client.query("SHOW META LIKE 'total_found%';")    
    a = results.to_a
    total_found = a[0]['Value'].to_i
    log_info "total_found: #{total_found}"

    r = {
      query_string: @q,
      time: 0,
      num_found: total_found
    }
    r[:results] = hits
    r[:time] = Time.now - t1
    my_render r
  ensure
    @mysql_client.close unless @mysql_client.nil?
  end

  private

  def action_ending
    return if @manticore.nil?
    @manticore.close
  end
  
  def add_work_info(rows)
    rows.each do |row|
      w = Work.find_by n: row[:work]
      next if w.nil?
      
      info = w.to_hash
      info.delete :juan # 要保留 sphinx 回傳的卷數
      row.merge! info

      #xf = XmlFile.find_by work: row[:work], vol: row[:vol]
      #unless xf.nil?
      #  row[:file] = xf.file
      #end
      
      # 例 J28nB214, CBETA 僅部份收錄
      #unless row.key? :file
      #  row[:file] = w.first_file
      #end
    end
  end

  def all_in_one_group_by_work(r)
    works = {}
    r[:results].each do |juan|
      w = juan[:work]
      unless works.key? w
        works[w] = {
          canon: juan[:canon],
          work: w,
          title: juan[:title],
          byline: juan[:byline],
          juans: []
        }
      end
      works[w][:juans] << { 
        juan: juan[:juan],
        term_hits: juan[:term_hits],
        kwics: juan[:kwics]
      }
    end
    r[:results] = works.values
  end

  # function calls:
  #   sphinx_search
  #   facet_by_sphinx_all
  #   kwic_by_juan
  #     kwic_boolean
  #       KwicService::search_near
  #       kwic_boolean_exclude
  #         KwicSearvice::search_juan
  def all_in_one_sub
    @canon_name = {}
    @exclude = nil

    # 1. Sphinx 的 NEAR，如果詞與詞有重疊，也會算找到,
    #    例如: 意樂 NEAR/7 增上意樂
    #    但這不是我們要的結果, 所以 sphinx 先傳回全部，再由 KWIC 過濾
    if @q.include?('NEAR')
      @mode = 'near'
      @start = 0
      @rows = 99_999
    elsif @q.match(/^"(.*?)" \-"(.*)"$/) # Sphinx 沒有 Exclude 功能，所以同 NEAR.
      @mode = 'exclude'
      @q = $1
      @exclude = $2
      @start = 0
      @rows = 99_999
      unless @exclude.include?(@q)
        raise CbetaError.new(400), "語法錯誤，Exclude #{@exclude} 應包含原始字串 #{@q}，原查詢字串：#{params[:q]}"
      end
    end

    @q_orig = @q
    unless @q.gsub(/\\"/, '').include? '"'
      @q = %("#{@q}")
    end

    @where = %{MATCH('@#{@text_field} #{@q}')} + @filter

    # 因為 max_matches 參數如果太大，會影響效率
    # 所以先計算最多會有多少 documents 符合條件
    estimate_max_matches

    if @order.empty?
      @order = 'ORDER BY canon_order ASC, work ASC, juan ASC'
    end

    r = sphinx_search(@fields, @where, @start, @rows, order: @order)

    # NEAR 跟 Exclude 的 Facet 不用 Sphinx 的
    if params[:facet] == '1' and not @q.include?('NEAR') and @exclude.nil?
      r['facet'] = {}
      facet_by_sphinx_all(r['facet'])
    end

    log_info "@exclude: #{@exclude.inspect}"
    if @exclude
      exclude_by_sphinx(r)
    end

    logger.debug "#{Time.now} sphinx search 完成"

    if @q.include?('NEAR')
      # 呼叫 KWIC 過濾 NEAR, 並取得所有出處、行號
      kwic_by_juan(r)
      r[:num_found] = r[:results].size
      r[:total_term_hits] = r[:results].inject(0) { |i, x| i + x[:term_hits] }
    end

    if @q.include?('NEAR') or not @exclude.nil?
      r[:facet] = my_facet(r[:results]) if @facet==1

      @start  = params.key?(:start)  ? params[:start].to_i  : 0
      @rows   = params.key?(:rows)   ? params[:rows].to_i   : 20
      r[:results] = r[:results][@start, @rows]
    end

    if params[:fields].nil? or params[:fields].include?('kwic')
      unless @q.include?('NEAR')
        kwic_by_juan(r)
        # r[:num_found] = r[:results].size
        # r[:total_term_hits] = r[:results].sum { it[:term_hits] }
        # log_info "kwic_by_juan 完成, num_found: #{r[:num_found]}, total_term_hits: #{r[:total_term_hits]}"
      end
    end

    if r.key?(:results)
      log_info "results size: #{r[:results].size}"
      # 回傳 行首資訊
      r[:results].each do |juan|
        if juan.key?(:kwics)
          juan[:kwics][:results].each do |kwic|
            file_basename = CBETA.get_xml_file_from_vol_and_work(kwic['vol'], juan[:work])
            kwic[:linehead] = CBETA.get_linehead(file_basename, kwic['lb'])
          end
        end
      end
    else
      log_info "#{__LINE__} r 沒有 results"
    end

    r
  ensure
    @mysql_client.close
  end

  def downsize_vars_array(vars)
    log_info "downsize_vars_array, vars: #{vars}"
    return vars if vars.size < 5
    vars2 = vars.clone
    r = []
    until vars2.empty?
      p = 1
      a = []
      while (p * vars2.first.size) < 60 # 組合數小於 100
        a << vars2.shift
        p *= a.last.size
        break if vars2.empty?
      end
      if vars2.size == 1
        a << vars2.shift
      end
      log_info "downsize_vars_array, a: #{a}"
      r << expand_vars_array(a, true)
    end
    log_info "downsize_vars_array, r: #{r}"
    r
  end
  
  def empty_result
    {
      query_string: @q,
      num_found: 0,
      total_term_hits: 0,
      results: []
    }
  end

  # 因為 max_matches 參數如果太大，會影響效率
  # 所以先計算最多會有多少 documents 符合條件
  def estimate_max_matches
    cmd = "SELECT COUNT(*) as docs FROM #{@index} WHERE #{@where};"
    log_info "estimate_max_matches, cmd: #{cmd}"
    r = @mysql_client.query(cmd)
    @max_matches = r.first['docs']
    log_info "max_matches: #{@max_matches}"

    # max_matches must be from 1 to 100M
    @max_matches = 1 if @max_matches == 0
  rescue => e
    raise CbetaError.new(500), "estimate_max_matches 發生錯誤, cmd: #{cmd}"
  end

  def exclude_by_sphinx(r1)
    r2 = sphinx_search_simple(@exclude) # 要被排除的
    log_info "exclude_by_sphinx, r2: #{r2.inspect}"

    h = {}
    r2.each do |juan|
      k = "#{juan[:work]}_#{juan[:juan]}"
      h[k] = juan[:term_hits]
    end
    log_info "exclude_by_sphinx, h: #{h.inspect}"

    r1[:total_term_hits] = 0
    i = 0
    while i < r1[:results].size
      juan = r1[:results][i]
      k = "#{juan[:work]}_#{juan[:juan]}"
      log_info "i: #{i}, k: #{k}"
      log_info "exclude 前 term_hits: #{juan[:term_hits]}"
      if h.key?(k)
        juan[:term_hits] -= h[k]
      end
      log_info "exclude 後 term_hits: #{juan[:term_hits]}"
      
      if juan[:term_hits] <= 0
        r1[:num_found] -= 1
        r1[:results].delete_at(i)
        next
      end

      r1[:total_term_hits] += juan[:term_hits]
      i += 1
    end
  end
  
  def exist_in_cbeta(q)
    log_info "exist_in_cbeta, q: #{q}"
    if params[:scope] == 'title'
      index = Rails.configuration.x.se.index_titles
      r = exist_in_index(q, index)
      log_info "exist_in_cbeta: #{r}"
      r
    end

    r = exist_in_index(q, Rails.configuration.x.se.index_text)
    return true if r

    r = exist_in_index(q, Rails.configuration.x.se.index_notes)
    return true if r

    r = exist_in_index(q, Rails.configuration.x.se.index_titles)
    return true if r
  end
  
  def exist_in_index(q, index)
    select = %(SELECT id FROM #{index} WHERE MATCH('"#{q}"') LIMIT 0, 1)
    result = @mysql_client.query(select)
    result.size > 0
  end

  def expand_vars_array(vars, chk_exist)
    log_info "expand_vars_array, vars: #{vars}, chk_exist: #{chk_exist}"
    t1 = Time.now
    #vars = downsize_vars_array(vars) if vars.size > 4
    args = vars[1..-1]
    a = vars[0].product(*args) # 各種可能組合
    a.map! { |x| x.join } # 合成字串
    return a unless chk_exist
    
    r = []
    a.each do |s|
      r << s if exist_in_cbeta(s)
    end
    log_info "#{__LINE__} expand_vars_array result: %s" % r.inspect
    r
  end
  
  # 參考 http://sphinxsearch.com/blog/2013/06/21/faceted-search-with-sphinx/
  def facet_by_sphinx(facet)
    read_dynasty_order if facet == 'dynasty'

    case facet
    when 'category'
      f1 = 'category_id'
      f2 = 'category_ids'
    when 'creator'
      f1 = f2 = 'creator_id'
    else
      f1 = f2 = facet
    end

    # ranker 會影響 weight 的計算方式
    # max_matches: 回傳筆數上限，影響記憶體用量、效率
    cmd = "SELECT GROUPBY() as #{f1}, "\
      "COUNT(*) as docs, "\
      "SUM(weight()) as hits "\
      "FROM #{@index} "\
      "WHERE #{@where} "\
      "GROUP BY #{f2} "\
      "ORDER BY hits DESC "\
      "LIMIT #{FACET_MAX} "\
      "OPTION ranker=#{RANKER}, max_matches=#{FACET_MAX};"

    result = @mysql_client.query(cmd, symbolize_keys: true)
    r = result.to_a
    
    case facet
    when 'canon'
      # 取得藏經名稱
      r.each do |row|
        c = Canon.find_by id2: row[:canon]
        row[:canon_name] = c.name unless c.nil?
      end
    when 'category'
      # 取得部類名稱
      fn = Rails.root.join('data-static', 'categories.json')
      categories = JSON.parse(File.read(fn))
      r.each do |row|
        id = row[:category_id].to_s
        row['category_name'] = categories[id]
      end
    when 'creator'
      r.each do |row|
        row[:creator_id] = "A%06d" % row[:creator_id]
        person = Person.find_by(id2: row[:creator_id])
        if person.nil?
          Rails.logger.debug "Person model 無此 ID: #{row[:creator_id]}"
        else
          row[:creator_name] = person.name
        end
      end
    when 'dynasty'
      r.sort_by! do |x|
        if @dynasty_order.key?(x[:dynasty])
          @dynasty_order[x[:dynasty]]
        else
          999
        end
      end
    when 'work'
      # 取得 佛典 title
      r.each do |row|
        id = row[:category_id].to_s
        w = Work.find_by n: row[:work]
        row['title'] = w.title unless w.nil?
      end
    end
    r
  end

  def facet_by_sphinx_all(dest)
    %w[category creator dynasty work canon].each do |f|
      dest[f] = facet_by_sphinx(f)
    end
  end
  
  def get_query_variants(q)
    log_info "get_query_variants, q: #{q}"
    remove_puncs_from_query
    vars = []
    q.each_char do |c|
      v = Variant.find_by(k: c)
      vars << Set[c]
      unless v.nil?
        vars[-1].merge(v.vars.split(','))
      end
      vars[-1] = vars[-1].to_a
    end
    vars = downsize_vars_array(vars)
    return expand_vars_array(vars, true)
  end
  
  def get_hit_count(where)
    select = %(SELECT sum(weight()) as sum FROM #{@index} WHERE #{where} OPTION ranker=#{RANKER};)
    r = @mysql_client.query(select)
    return 0 if r.count==0
    r.each do |row|
      return row['sum']
    end
  rescue Mysql2::Error
    logger.fatal "SQL command: #{select}"
    logger.fatal $!
    raise CbetaError.new(500), "Mysql2::Error, SQL command: #{select}\n#{$!}"
  end
  
  def init
    @referer_cn = referer_cn?
    @max_matches = 999_999

    unless params.key? :q
      render plain: '缺少必要參數：q'
      return false
    end
    
    @q = Gaiji.replace_zzs_with_pua(params[:q]) # 將 組字式 取代為 Unicode PUA
    if @q.blank?
      render plain: 'q 參數不能是空的'
      return false
    end
    
    @mode = 'normal'
    @use_cache = params.key?(:cache) ? (params[:cache]=='1') : true
    @start  = params.key?(:start)  ? params[:start].to_i  : 0
    @rows   = params.key?(:rows)   ? params[:rows].to_i   : 20
    @around = params.key?(:around) ? params[:around].to_i : 10
    @facet  = params.key?(:facet)  ? params[:facet].to_i  : 0
    @inline_note = params.key?(:note) ? params[:note]=='1' : true
    @score_min = params.key?(:score_min) ? params[:score_min].to_i : SCORE_MIN
    @text_field = @inline_note ? 'content' : 'content_without_notes'

    case action_name
    when 'notes' then init_notes
    when 'similar'
      @index = Rails.configuration.x.se.index_chunks
      @gain  = params.key?(:gain)  ? params[:gain].to_i : 2
      @penalty  = params.key?(:penalty)  ? params[:penalty].to_i : -1
      raise CbetaError.new(400), 'gain 參數 必須 >= 0' if @gain < 0
      raise CbetaError.new(400), 'penalty 參數 必須 <= 0' if @penalty > 0
    when 'title'
    when 'variants'
      init_fields
      @index = 
        if params[:scope] == 'title'
          Rails.configuration.x.se.index_titles
        else
          Rails.configuration.x.se.index_text
        end
    else
      init_fields
      @index = Rails.configuration.x.se.index_text
    end

    log_info "index: #{@index}"
    
    init_order unless action_name == 'similar'
    set_filter

    @manticore = ManticoreService.new
    @mysql_client = @manticore.open
  end

  def init_fields
    all = {
      'id' => 'id',
      'term_hits' => 'weight()',
      'canon' => 'canon',
      'category' => 'category', 
      'file' => 'xml_file',
      'work' => 'work',
      'juan' => 'juan',
      'title' => 'title',
      'byline' => 'byline',
      'creators' => 'creators',
      'creators_with_id' => 'creators_with_id',
      'time_dynasty' => 'dynasty',
      'time_from' => 'time_from',
      'time_to' => 'time_to',
      'juan_list' => 'juan_list'
    }

    if params.key? :fields
      a = params[:fields].split(',')
      all.delete_if { |k, v| !a.include?(k) }
    end

    a = []
    all.each do |k, v|
      if k == v
        a << k
      else
        a << "#{v} as #{k}"
      end
    end

    @fields = a.join(', ')
  end

  def init_notes
    @index = Rails.configuration.x.se.index_notes
    q = @q.sub(/~\d+$/, '') # 拿掉 near ~ 後面的數字
    q.gsub!(/[\-!]".*?"/, '')
    keys = q.split(/["\-\| ]/)
    keys.delete('')
    s = keys.join(' ')

    @fields = "id, note_place, canon, category, vol, file, "\
      "work, title, juan, lb, n, content, content_w_puncs, prefix, suffix"
  end
  
  # 排序欄位最多只能有五個，否則會出現如下錯誤：
  # Mysql2::Error (index cbeta122: too many sort-by attributes; maximum count is 5)
  def init_order
    @order = ''
    count = 0

    unless params.key? :order
      if action_name == 'notes'
        @order = "ORDER BY canon_order ASC, vol ASC, lb ASC"
      end
      return
    end

    tokens = params[:order].split(',')
    orders = []
    tokens.each do |t|
      if t.end_with? '+'
        field = t[0..-2]
        dir = 'ASC'
      elsif t.end_with? '-'
        field = t[0..-2]
        dir = 'DESC'
      else
        field = t
        dir = field=='term_hits' ? "DESC" : "ASC"
      end
      order = case field
      when 'canon'
        "canon_order #{dir}"
      when 'time_from', 'time_to'
        @fields += ",(#{field} <> 0) AS has_#{field}"
        "has_#{field} DESC, #{field} #{dir}"
      else
        "#{field} #{dir}"
      end
      orders << order
    end
    @order = "ORDER BY " + orders.join(',')
  end

  def mark_title(title, query)
    r = ''
    title.each_char do |c|
      if query.include?(c)
        r << "<mark>#{c}</mark>"
      else
        r << c
      end
    end
    r.gsub!('</mark><mark>', '')
    r
  end

  def my_facet(juans)
    canon = {}
    category = {}
    creator = {}
    dynasty = {}
    work = {}

    juans.each do |j|
      my_facet_catetory(j, category)
      my_facet_creator(j, creator)
      my_facet_dynasty(j, dynasty)
      my_facet_work(j, work)
      my_facet_canon(j, canon)
    end

    { 
      category: category.values,
      creator: creator.values,
      dynasty: dynasty.values,
      work: work.values,
      canon: canon.values
    }
  end

  def my_facet_canon(juan, dest)
    k = juan[:canon]

    name = @canon_name[k]
    if name.nil?
      name = Canon.find_by(id2: k).name
      @canon_name[k] = name
    end

    unless dest.key?(k)
      dest[k] = { canon: k, canon_name: name, hits: 0 }
      dest[k][:docs] = 0 unless action_name == 'similar'
    end

    dest[k][:hits] += (juan[:term_hits] || 1)
    dest[k][:docs] += 1 unless action_name == 'similar'
  end

  # 部類可能有多值, 例如 T0310 的部類: "寶積部類,淨土宗部類"
  def my_facet_catetory(juan, dest)
    juan[:category].split(',').each do |c|
      unless dest.key?(c)
        dest[c] = { category_name: c, hits: 0 }
        dest[c][:docs] = 0 unless action_name == 'similar'
      end
      dest[c][:hits] += (juan[:term_hits] || 1)
      dest[c][:docs] += 1 unless action_name == 'similar'
    end
  end

  def my_facet_creator(juan, dest)
    # ex: "龍樹(A001482);鳩摩羅什(A001583)"
    juan[:creators_with_id].split(';').each do |c|
      name, id = c.scan(/^(.*)\((.*)\)$/).first
      unless dest.key?(id)
        dest[id] = { creator_id: id, creator_name: name, hits: 0 }
        dest[id][:docs] = 0 unless action_name == 'similar'
      end
      dest[id][:hits] += (juan[:term_hits] || 1)
      dest[id][:docs] += 1 unless action_name == 'similar'
    end
  end

  def my_facet_dynasty(juan, dest)
    d = juan[:time_dynasty] || juan[:dynasty]
    unless dest.key?(d)
      dest[d] = { dynasty: d, hits: 0 }
      dest[d][:docs] = 0 unless action_name == 'similar'
    end
    dest[d][:hits] += (juan[:term_hits] || 1)
    dest[d][:docs] += 1 unless action_name == 'similar'
  end

  def my_facet_work(juan, dest)
    k = juan[:work]
    unless dest.key?(k)
      dest[k] = { work: k, title: juan[:title], hits: 0 }
      dest[k][:docs] = 0 unless action_name == 'similar'
    end
    dest[k][:hits] += (juan[:term_hits] || 1)
    dest[k][:docs] += 1 unless action_name == 'similar'
  end

  def kwic_by_juan(r)
    base = Rails.configuration.x.kwic.base
    se = KwicService.new(base, @inline_note)
    r[:results].each do |juan|
      log_info "kwic_by_juan, work: #{juan[:work]}, juan: #{juan[:juan]}"
      opts = {
        work: juan[:work],
        juan: juan[:juan].to_i,
        around: @around,
        mark: true,
        rows: 99999,
        referer_cn: @referer_cn
      }
      juan[:kwics] = kwic_boolean(se, opts)
      
      if juan[:kwics].nil?
        raise CbetaError.new(500), "kwic_boolean 回傳 nil" 
      end

      juan[:kwics][:results].sort_by! { |x| x['vol'] + x['lb'] }
      juan[:term_hits] = juan[:kwics][:num_found]
    end
    r[:results].delete_if { |x| x[:kwics][:results].empty? }

    # 如果有指定不要 kwics 欄位
    if params.key?(:fields) and !params[:fields].include?('kwics')
      r[:results].each { |x| x.delete(:kwics) }
    end
  end
  
  # boolean search 回傳 kwic
  def kwic_boolean(se, opts)
    if @q.match?(/ NEAR\/(\d+) /)
      return se.search_near(@q, opts)
    end

    if @exclude
      return kwic_boolean_exclude(se, opts)
    end

    a = []
    num_found = 0

    q = @q_orig
    log_debug "q: #{q}"
    q.gsub!(/[!\-]"[^"]+"/, '') # 去除 not 之後的關鍵字
    q.gsub!(/(?<!\\)"/, '') # 沒有 escape 的單引號、雙引號 去掉
    q.gsub!(/\\(['"])/, '\1')
    log_debug "q: #{q}"
    keys = q.split

    keys.each do |k|
      k2 = k.downcase
      h = se.search(k2, opts)
      num_found += h[:num_found]
      a += h[:results]
    end

    a.each do |h|
      # 卷可能跨冊號，必須保留冊號
      h.delete('work')
      h.delete('juan')
    end

    { num_found: num_found, results: a}
  end

  def kwic_boolean_exclude(se, opts)
    q = @q.sub(/^"(.*)"$/, '\1')
    @exclude.match(/^#{q}(.*)$/) do
      opts[:negative_lookahead] = $1
      return se.search_juan(q, opts)
    end

    @exclude.match(/^(.*?)#{q}$/) do
      opts[:negative_lookbehind] = $1
      t1 = Time.now
      r = se.search_juan(q, opts)
      #logger.debug "search_juan 花費時間: #{Time.now - t1}"
      return r
    end

    raise CbetaError.new(400), "語法錯誤，Exclude #{@exclude} 應包含原始字串 #{q}，原查詢字串：#{params[:q]}"
  end

  def read_dynasty_order
    @dynasty_order = {}
    fn = Rails.root.join('data-static', 'dynasty-order.csv')
    i = 1
    CSV.foreach(fn, headers: true) do |row|
      d = row['dynasty']
      @dynasty_order[d] = i
      i += 1
    end
  end

  # 去除標點
  def remove_puncs_from_query
    # 允許 NEAR/7 語法，數字要保留
    @q = CbetaString.new(allow_digit: true).remove_puncs(@q)
  end

  def set_filter
    @filter = ''
    set_filter_category
    set_filter_creator
    set_filter_canon    
    
    if params.key? :dynasty
      s = params[:dynasty]
      if s.include? ','
        a = s.split(',')
        a.map! { |x| "'#{x}'"}
        @filter << " AND dynasty IN (%s)" % a.join(',')
      else
        @filter << " AND dynasty='#{s}'"
      end
    end
    
    if params.key? :time
      s = params[:time]
      if s.include? '..'
        t1, t2 = s.split('..')
        @filter << " AND time_from<=#{t2} AND time_to>=#{t1}"
      else
        @filter << " AND time_from<=#{s} AND time_to>=#{s}"
      end
    end
    
    if params.key? :work
      @filter << " AND work='%s'" % params[:work]
    end
    
    if params.key? :works
      works = Set.new
      params[:works].split(',').each do |w|
        works << w
      end
      works = works.to_a
      works.map! { |x| %('#{x}')}
      @filter << " AND work IN (%s)" % works.join(',')
    end

    if params.key? :work_type
      t = params[:work_type]
      @filter << " AND work_type='#{t}'"
    end
  end

  def set_filter_canon
    if @referer_cn
      a = Rails.configuration.cn_filter.map { |x| "'#{x}'" }
      r = a.join(',')
      @filter << " AND canon NOT IN (#{r})"
    end

    return unless params.key?(:canon) 
    
    s = params[:canon]
    if s.include?(',')
      a = s.split(',').map { |x| "'#{x}'"}
      @filter << " AND canon IN (%s)" % a.join(',')
    else
      @filter << " AND canon='#{s}'"
    end
  end

  # a,b+c,d 表示 (a OR b) AND (c OR d)
  def set_filter_category
    return unless params.key? :category
    and_conditions = []
    params[:category].split('+').each do |exp|
      names = exp.split(',')
      if names.size == 1
        n = Category.get_n_by_name(exp)
        and_conditions << "category_ids = #{n}"
      else # 多值
        set = Set.new
        names.each do |name|
          set << Category.get_n_by_name(name).to_s
        end
        and_conditions << "(category_ids IN (%s))" % set.to_a.join(',')
      end
    end

    @filter += ' AND ' + and_conditions.join(' AND ')
  end
  
  # a,b+c,d 表示 (a OR b) AND (c OR d)
  def set_filter_creator
    return unless params.key? :creator
    and_conditions = []
    params[:creator].split('+').each do |exp|
      set = Set.new
      exp.split(',').each do |c|
        set << c.sub(/^A0*(\d+)$/, '\1')
      end
      s = set.to_a.join(',')
      and_conditions << "creator_id IN (#{s})"
    end

    @filter += ' AND ' + and_conditions.join(' AND ')
  end

  def manticore_search(user_args={})
    args = user_args.with_defaults(
      rows: @rows, 
      ranker: RANKER,
      order: '',
      count_hits: true
    )
    t1 = Time.now

    @select = %(
      SELECT #{args[:fields]}
      FROM #{@index} 
      WHERE #{args[:where]} #{args[:order]} 
      LIMIT #{args[:rows]} 
      OPTION ranker=#{args[:ranker]}, max_matches=#{@max_matches}
    ).gsub(/\s+/, " ").strip
    
    @select += " FACET #{args[:facet]}" if args.key?(:facet)
    log("select: #{@select}", __LINE__)
    begin
      results = @mysql_client.query(@select, symbolize_keys: true)
    end
    log_info "#{__LINE__} mysql query 完成"

    hits = results.to_a
    return hits if @mode == 'group'
    log_info "#{__LINE__} hits size: #{hits.size}"
    
    #add_work_info(hits)
    
    if args.key?(:facet)
      if @mysql_client.next_result
        rows = @mysql_client.store_result
        facet_result = rows.to_a
        pp facet_result
      end
    end    
    
    results = @mysql_client.query("SHOW META LIKE 'total_found%';")
    
    a = results.to_a
    total_found = a[0]['Value'].to_i
    log_info "#{__LINE__} total_found: #{total_found}"
    
    total_term_hits = nil
    if args[:count_hits]
      if total_found == 0
        total_term_hits = 0
      else
        # ranker 如果是 proximity_bm25, 執行以下動作會當機
        select2 = <<~SQL
          SELECT sum(weight()) as sum FROM #{@index} 
          WHERE #{args[:where]} 
          OPTION ranker=#{args[:ranker]}, max_matches=#{@max_matches}
        SQL
        log_info "#{__LINE__} 計算 total_term_hits: #{select2}"
        r = @mysql_client.query(select2)
        total_term_hits = r.to_a[0]['sum']
        log_info "#{__LINE__} total_term_hits: #{total_term_hits}"
      end
    end
    
    r = {
      query_string: @q,
      SQL: @select,
      time: Time.now - t1,
      num_found: total_found,
      cache_key: nil
    }
    r[:total_term_hits] = total_term_hits unless total_term_hits.nil?
    r[:facet] = facet_result if args.key?(:facet)
    r[:results] = hits
    r
  end

  def notes_highlight(r)
    q1 = params[:q].sub(/\A"(.*)"\z/, '\1') # 未去標點的 Query String

    # 允許標點差異的 regular expression
    q2 = @q.sub(/\A"(.*)"\z/, '\1')
    s = q2.chars.join("[【】，〔－〕＊。]*")
    log_info "notes_highlight, exp: #{s}"
    exp = Regexp.new(s)

    r[:results].each do |h|
      h[:highlight] = h[:content_w_puncs].gsub(q1, "<mark>#{q1}</mark>")
      unless h[:highlight].include?('<mark>')
        h[:highlight] = h[:content_w_puncs].gsub(exp, '<mark>\0</mark>')
      end

      notes_inline_around(h) if h[:note_place] == 'inline'
      
      h.delete(:content_w_puncs)
      h.delete(:prefix)
      h.delete(:suffix)
      h[:content] = Gaiji.replace_pua_with_zzs(h[:content])
      h[:highlight] = Gaiji.replace_pua_with_zzs(h[:highlight])
    end
  end

  def notes_inline_around(h)
    log_info "notes_inline_around, highlight: #{h[:highlight]}"
    hh = h[:highlight]
    hh.match(/^(.*?)(<mark>.*<\/mark>)(.*)$/) do |m|
      hh = m[2]
      s = h[:prefix] + '(' + m[1]
      prefix = s[-@around..-1] || s
      s = m[3] + ')' + h[:suffix]
      suffix = s[0, @around]
      h[:highlight] = "#{prefix}#{hh}#{suffix}"
    end
    h.delete(:n)
  end

  def similar_sub
    log_info "similar_sub"
    remove_puncs_from_query
    @canon_name = {}
    @max_matches = params[:k] || SIMILAR_K
    data = {
      fields: 'id, canon, category, work, title, juan, creators_with_id, dynasty, linehead, content',
      where: %{MATCH('"#{@q}"/0.5')} + @filter,
      rows: @max_matches,
      ranker: 'proximity_bm25',
      count_hits: false
    }
    where = %{MATCH('"#{@q}"')} + @filter

    r = manticore_search(data)
    hits = r[:results]

    log_info "begin similar_smith_waterman"
    similar_smith_waterman(hits)
    log_info "begin similar_rm_duplicate"
    similar_rm_duplicate(hits)
    hits.sort_by! { |x| -x[:score] }

    r.delete(:total_term_hits)
    r[:num_found] = hits.size

    if params[:facet] == '1'
      r[:facet] = my_facet(r[:results])
    end
    
    r
  end

  def similar_smith_waterman(hits)
    log_info "begin similar_smith_waterman, hits size: #{hits.size}, gain: #{@gain}, penalty: #{@penalty}"

    cs = CbetaString.new(allow_digit: true, allow_space: false)
    i = 0
    while i < hits.size
      node = hits[i]
      text = cs.remove_puncs(node[:content])
      #text = node[:content]
      
      # 去除完全符合的
      if text.include?(@q)
        hits.delete_at(i)
        next
      end

      sw = SmithWaterman.new(@q, text, gain: @gain, penalty: @penalty)
      sw.align!
      if sw.score < @score_min
        hits.delete_at(i)
        next
      end

      node[:score] = sw.score
      node[:highlight] = sw.alignment_inspect_b

      # 只要 match 到的區域，由區塊內第一字開始，或是延續到最後一字，就砍掉。
      # 卷首 或 卷尾 除外
      if node[:highlight].start_with?('<mark>') and node[:position_in_juan] != 'start'
        hits.delete_at(i)
      elsif node[:highlight].end_with?('</mark>') and node[:position_in_juan] != 'end'
        hits.delete_at(i)
      else
        i += 1
      end
    end
    log_info "end similar_smith_waterman"
  end

  def similar_rm_duplicate(hits)
    i = 0
    nodes = {}
    while i < hits.size
      node = hits[i]
      node2 = nil

      if nodes.key?(node[:id]-1)
        node2 = nodes[node[:id]-1]
      end
      
      if node2.nil? and nodes.key?(node[:id]+1)
        node2 = nodes[node[:id]+1]
      end

      if node2.nil?
        i += 1
        nodes[node[:id]] = node
        next
      end
      
      regx = /<mark>.*?<\/mark>/
      mark1 = node[:highlight].match(regx).to_s
      mark2 = node2[:highlight].match(regx).to_s

      # 去除重複
      if mark1 == mark2
        hits.delete_at(i)
        next
      end

      nodes[node[:id]] = node
      i += 1
    end
  end

  def sphinx_search(fields, where, start, rows, order: nil, facet: nil)
    log_info "sphinx_search 開始, where: #{where}, max_matches: #{@max_matches}"
    t1 = Time.now

    if start >= @max_matches
      raise CbetaError.new(400), "start 參數超出範圍: #{start}, max_matches: #{@max_matches}, where: #{where}"
    end
    
    @select = %(
      SELECT #{fields}
      FROM #{@index} 
      WHERE #{where} #{order} 
      LIMIT #{start}, #{rows} 
      OPTION ranker=#{RANKER}, max_matches=#{@max_matches}
    ).gsub(/\s+/, " ").strip
    
    @select += " FACET #{facet}" unless facet.nil?
    log_info "select: #{@select}"
    begin
      results = @mysql_client.query(@select, symbolize_keys: true)
    rescue
      logger.fatal $!
      logger.fatal "environment: #{Rails.env}"
      logger.fatal "select: #{@select}"
      raise
    end

    hits = results.to_a
    return hits if @mode == 'group'
    log_info "#{__LINE__} hits size: #{hits.size}"
    
    #add_work_info(hits)
    
    unless facet.nil?
      if @mysql_client.next_result
        rows = @mysql_client.store_result
        facet_result = rows.to_a
        pp facet_result
      end
    end    
    
    results = @mysql_client.query("SHOW META LIKE 'total_found%';")
    
    a = results.to_a
    total_found = a[0]['Value'].to_i
    log_info "total_found: #{total_found}"
    
    if total_found == 0
      total_term_hits = 0
    else
      select2 = %(SELECT sum(weight()) as sum FROM #{@index} WHERE #{where} OPTION ranker=#{RANKER};)
      r = @mysql_client.query(select2)
      total_term_hits = r.to_a[0]['sum']
    end
    
    r = {
      query_string: @q,
      SQL: @select,
      time: Time.now - t1,
      num_found: total_found,
      total_term_hits: total_term_hits,
      cache_key: nil
    }
    r[:facet] = facet_result unless facet.nil?
    r[:results] = hits
    r
  end

  def sphinx_search_simple(q)
    logger.debug "begin sphinx_search_simple, q: #{q}"

    where = %{MATCH('@#{@text_field} "#{q}"')} + @filter
    fields = 'weight() as term_hits, work, juan'

    select = %(
      SELECT #{fields}
      FROM #{@index}
      WHERE #{where}
      LIMIT 0, #{@max_matches}
      OPTION ranker=#{RANKER}, max_matches=#{@max_matches}
    ).gsub(/\s+/, " ").strip
    logger.debug select
    
    results = @mysql_client.query(select, symbolize_keys: true)
    results.to_a
  end

  def sphinx_select(fields, opts={})
    @opts = {
      where: @where,
      start: @start,
      rows: @rows
    }
    @opts.merge!(opts)
    select = "SELECT #{fields} FROM #{@index} WHERE #{@opts[:where]}"
    select += " GROUP BY " + @opts[:group] if @opts.key?(:group)
    select += " ORDER BY " + @opts[:order] if @opts.key?(:order)
    select += " LIMIT #{@opts[:start]}, #{@opts[:rows]} OPTION ranker=#{RANKER}"
    unless @max_matches.nil?
      select += ", max_matches=#{@max_matches}"
    end
    results = @mysql_client.query(select, symbolize_keys: true)    
    results.to_a
  end

  def sphinx_total_found
    # total_found: 上次搜尋符合的 documents 數量
    r = @mysql_client.query("SHOW META LIKE 'total_found%';")
    a = r.to_a
    found = a[0]['Value'].to_i

    if found == 0
      term_hits = 0
    else
      select2 = %(SELECT sum(weight()) as sum FROM #{@index} WHERE #{@where} OPTION ranker=#{RANKER};)
      r = @mysql_client.query(select2)
      term_hits = r.to_a[0]['sum']
    end

    return found, term_hits
  end

  # 根據異體字表，回傳各種可能異體字串及搜尋結果筆數
  # 效率測試：
  #   * 無上正等正覺
  #   * 大比丘三千威儀
  #   * 阿耨多羅三藐三菩提
  def variants_sub
    log_info "scope: #{params[:scope]}"
    t1 = Time.now
    remove_puncs_from_query
    log_info "variants_sub, q: #{@q}"
    q_ary = get_query_variants(@q)
    
    if @q.include? '菩薩'
      q = @q.gsub('菩薩', '𦬇')
      a = get_query_variants(q)
      a.delete_if {|s| s.include? '菩薩' } # 去除重複
      q_ary += a
    end
    
    results = []
    q_ary.each do |q|
      next if q == @q

      where = %{MATCH('@content "#{q}"')}
      where << @filter
  
      i = get_hit_count(where)
      results << { q: q, hits: i } unless i==0
    end
    
    {
      time: Time.now - t1,
      num_found: results.size,
      cache_key: nil,
      possibility: q_ary.size,
      results: results
    }
  end

  def error_handler(e)
    logger.fatal $!
    logger.fatal "environment: #{Rails.env}"
    logger.fatal "select: #{@select}"
    logger.fatal e.backtrace.join("\n")

    r = empty_result
    r[:select] = @select unless @select.nil?
    #r[:code] = e.code
    r[:error] = e.message
    r[:backtrace] = e.backtrace
    my_render r
  end
end
