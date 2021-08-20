# all_in_one
#   Exclude X -Y
#     1. 先呼叫 Sphinx 取得全部符合 X 的卷數
#     2. 每一卷呼叫 KWIC 過濾 -Y
#        2.1 取得本卷符合 X 的位置
#        2.2 讀取前後文，過濾 -Y
#     3. 計算總筆數、Facet

require 'csv'
require 'open3'

class SphinxController < ApplicationController
  MAX_JUAN = 999_999
  OPTION = 'ranker=wordcount,max_matches=9999999'
  before_action :init
  
  # 2019-11-01 決定不以經做 group, 因為不能以經的 term_hits 做排序
  def all_in_one
    logger.debug Time.now
    @mode = 'extend' # 允許 boolean search
    remove_puncs_from_query
    return empty_result if @q.empty?

    t1 = Time.now
    key = "#{Rails.configuration.x.v}/%s" % params.to_s
    r = Rails.cache.fetch(key) do
      all_in_one_sub
    end
    r[:cache_key] = key
    r[:time] = Time.now - t1
    
    my_render r
  rescue Exception => e
    e.backtrace.each { |s| logger.debug s }
    r = { 
      num_found: 0,
      params: params,
      error: e.message + "\n" + e.backtrace.join("\n")
    }
    my_render r
  end

  def index
    remove_puncs_from_query
    
    return empty_result if @q.empty?
    
    @mysql_client = sphinx_mysql_connection
    where = %{MATCH('"#{@q}"')} + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    @mysql_client.close
    my_render r
  rescue
    r = { num_found: 0, error: $!, sphinx_select: @select }
    my_render r
  end  

  def test
    remove_puncs_from_query
    
    return empty_result if @q.empty?
    
    @mysql_client = sphinx_mysql_connection
    where = %{MATCH('#{@q}')} + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    @mysql_client.close
    my_render r
  rescue
    r = { num_found: 0, error: $!, sphinx_select: @select }
    my_render r
  end  

  def extended
    @mode = 'extend'
    remove_puncs_from_query
    
    return empty_result if @q.empty?
    
    @mysql_client = sphinx_mysql_connection
    where = "MATCH('#{@q}')" + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    @mysql_client.close
    my_render r
  end

  def footnotes
    @mode = 'extend'
    #remove_puncs_from_query
    
    return empty_result if @q.empty?
    
    @mysql_client = sphinx_mysql_connection
    @where = "MATCH('#{@q}')" + @filter
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

    @mysql_client.close
    my_render r
  end

  def facet
    @mode = 'extend'
    remove_puncs_from_query

    raise CbetaError.new(400), "缺少 q 參數" if @q.empty?

    @mysql_client = sphinx_mysql_connection
    @where = %{MATCH('"#{@q}"')} + @filter
    
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
        
    @mysql_client.close
    
    my_render r
  rescue CbetaError => e
    r = empty_result
    r[:error] = { code: e.code, message: $!, backtrace: e.backtrace }
    my_render(r)
  end
  
  def fuzzy
    remove_puncs_from_query
    
    return empty_result if @q.empty?
    
    @mysql_client = sphinx_mysql_connection
    where = %{MATCH('#{@q}')} + @filter
    r = sphinx_search(@fields, where, @start, @rows, order: @order)
    @mysql_client.close
    my_render r
  rescue
    r = { num_found: 0, error: $! }
    my_render r
  end

  # 根據異體字表，回傳各種可能異體字串及搜尋結果筆數
  # 效率測試：
  #   * 無上正等正覺
  #   * 大比丘三千威儀
  #   * 阿耨多羅三藐三菩提
  def variants
    t1 = Time.now
    @mysql_client = sphinx_mysql_connection
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
      where = %{MATCH('"#{q}"')} + @filter
      i = get_hit_count(where)
      results << { q: q, hits: i } unless i==0
    end
    @mysql_client.close
    
    r = {
      time: Time.now - t1,
      num_found: results.size,
      possibility: q_ary.size,
      results: results
    }
    my_render r
  end

  # 以簡體字查詢
  def sc
    raise CbetaError.new(400), "q 參數長度不得大於 50" if params[:q].size > 50

    t1 = Time.now

    # 簡轉繁
    cmd = 'opencc -c s2tw'
    @q, status = Open3.capture2(cmd, stdin_data: params[:q])

    @mysql_client = sphinx_mysql_connection
    where = %{MATCH('"#{@q}"')} + @filter
    i = get_hit_count(where)
    @mysql_client.close
    
    r = {
      time: Time.now - t1,
      q: @q,
      hits: i
    }
    my_render r
  rescue CbetaError => e
    r = { error: { code: e.code, message: $!, backtrace: e.backtrace } }
    my_render(r)
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
    return empty_result if @q.empty?
    t1 = Time.now
    @index = Rails.application.config.x.sphinx_titles
    @where = %{MATCH('#{@q}')} + @filter
    select = "SELECT work, title FROM #{@index}"\
      " WHERE #{@where} ORDER BY canon_order ASC"\
      " LIMIT #{@start}, #{@rows} OPTION #{OPTION}"
    @mysql_client = sphinx_mysql_connection
    results = @mysql_client.query(select, symbolize_keys: true)    
    @mysql_client.close

    hits = results.to_a
    hits.each do |h|
      w = Work.find_by(n: h[:work])
      h[:byline] = w.byline
      h[:juan] = w.juan
      h[:creators_with_id] = w.creators_with_id
      h[:time_dynasty] = w.time_dynasty
      h[:time_from] = w.time_from
      h[:time_to] = w.time_to
    end

    r = {
      query_string: @q,
      time: 0,
      num_found: hits.size,
    }
    r[:results] = hits
    r[:time] = Time.now - t1
    my_render r
  end

  private
  
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
    @mysql_client = sphinx_mysql_connection

    # 1. Sphinx 的 NEAR，如果詞與詞有重疊，也會算找到,
    #    例如: 意樂 NEAR/7 增上意樂
    #    但這不是我們要的結果, 所以 sphinx 先傳回全部，再由 KWIC 過濾
    if @q.include?('NEAR')
      @start = 0
      @rows = 99_999
    end

    # Sphinx 沒有 Exclude 功能，所以同 NEAR.
    @exclude = nil
    if @q.match(/^"(.*?)" \-"(.*)"$/)
      @q = $1
      @exclude = $2
      @start = 0
      @rows = 99_999
      unless @exclude.include?(@q)
        raise CbetaError.new(400), "語法錯誤，Exclude #{@exclude} 應包含原始字串 #{@q}，原查詢字串：#{params[:q]}"
      end
    end

    unless @q.include? '"'
      @q = %("#{@q}")
    end
    @where = %{MATCH('#{@q}')} + @filter

    if @order.empty?
      @order = 'ORDER BY canon_order ASC'
    end

    r = sphinx_search(@fields, @where, @start, @rows, order: @order)

    # NEAR 跟 Exclude 的 Facet 不用 Sphinx 的
    if params[:facet] == '1' and not @q.include?('NEAR') and @exclude.nil?
      r['facet'] = {}
      facet_by_sphinx_all(r['facet'])
    end

    if @exclude
      exclude_by_sphinx(r)
    end

    @mysql_client.close
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

    unless @q.include?('NEAR')
      kwic_by_juan(r)
    end

    r
  end

  def downsize_vars_array(vars)
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
      r << expand_vars_array(a, true)
    end
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

  def exclude_by_sphinx(r1)
    r2 = sphinx_search_simple(@exclude)
    h = {}
    r2.each do |juan|
      k = "#{juan[:work]}_#{juan[:juan]}"
      h[k] = juan[:term_hits]
    end

    r1[:total_term_hits] = 0
    i = 0
    while i < r1[:results].size
      juan = r1[:results][i]
      k = "#{juan[:work]}_#{juan[:juan]}"
      if h.key?(k)
        juan[:term_hits] -= h[k]
      end
      
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
    select = %(SELECT id FROM #{@index} WHERE MATCH('"#{q}"') LIMIT 0, 1)
    result = @mysql_client.query(select)
    if result.size == 0
      return false
    else
      return true
    end    
  end
  
  def expand_vars_array(vars, chk_exist)
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

    cmd = "SELECT GROUPBY() as #{f1}, "\
      "COUNT(*) as docs, "\
      "SUM(weight()) as hits "\
      "FROM #{@index} "\
      "WHERE #{@where} "\
      "GROUP BY #{f2} "\
      "ORDER BY hits DESC "\
      "LIMIT 9999999 "\
      "OPTION ranker=wordcount;" # 這會影響 weight 的計算方式

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
      fn = File.join(Rails.application.config.cbeta_data, 'category', 'categories.json')
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
      # 取得 典籍 title
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
    remove_puncs_from_query
    vars = []
    q.each_char do |c|
      v = Variant.find_by(k: c)
      vars << [c]
      unless v.nil?
        vars[-1] += v.vars.split(',')
      end
    end
    vars = downsize_vars_array(vars)
    return expand_vars_array(vars, false)
  end
  
  def get_hit_count(where)
    select = %(SELECT sum(weight()) as sum FROM #{@index} WHERE #{where} OPTION #{OPTION};)
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
    unless params.key? :q
      render plain: '缺少必要參數：q'
      return false
    end
    
    @q = handle_zzs(params[:q]) # 將 組字式 取代為 Unicode PUA
    if @q.blank?
      render plain: 'q 參數不能是空的'
      return false
    end
    
    @mode = 'normal'
    @start  = params.key?(:start)  ? params[:start].to_i  : 0
    @rows   = params.key?(:rows)   ? params[:rows].to_i   : 20
    @around = params.key?(:around) ? params[:around].to_i : 10
    @facet  = params.key?(:facet)  ? params[:facet].to_i  : 0

    case action_name
    when 'footnotes'
      init_footnotes
    when 'title'
      init_title
    else
      @fields = 'id'\
        ', weight() as term_hits'\
        ', canon'\
        ', category'\
        ', xml_file as file'\
        ', work'\
        ', juan'\
        ', title'\
        ', byline'\
        ', creators, creators_with_id'\
        ', dynasty as time_dynasty, time_from, time_to'\
        ', juan_list'
  
      @index = Rails.application.config.sphinx_index
    end
    
    init_order    
    set_filter
  end

  def init_footnotes
    @index = Rails.configuration.x.sphinx_footnotes
    q = @q.sub(/~\d+$/, '') # 拿掉 near ~ 後面的數字
    q.gsub!(/[\-!]".*?"/, '')
    keys = q.split(/["\-\| ]/)
    keys.delete('')
    s = keys.join(' ')

    # http://sphinxsearch.com/docs/current/api-func-buildexcerpts.html
    @fields = "id, canon, category, vol, file, work, title, juan, lb, n, content, "\
      "SNIPPET(content, '#{@q}', 'limit=0', "\
      "'before_match=<mark>', 'after_match=</mark>') AS highlight"
  end
  
  def init_title
    @index = Rails.application.config.sphinx_index

    @fields = "id, canon, category, vol, file, work, title, juan, lb, n, content, "\
      "SNIPPET(content, '#{@q}', 'limit=0', "\
      "'before_match=<mark>', 'after_match=</mark>') AS highlight"
  end

  # 排序欄位最多只能有五個，否則會出現如下錯誤：
  # Mysql2::Error (index cbeta122: too many sort-by attributes; maximum count is 5)
  def init_order
    @order = ''
    count = 0
    return unless params.key? :order

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
      dest[k] = { canon: k, canon_name: name, hits: 0, docs: 0 }
    end
    dest[k][:hits] += juan[:term_hits]
    dest[k][:docs] += 1
  end

  # 部類可能有多值, 例如 T0310 的部類: "寶積部類,淨土宗部類"
  def my_facet_catetory(juan, dest)
    juan[:category].split(',').each do |c|
      unless dest.key?(c)
        dest[c] = { category_name: c, hits: 0, docs: 0 }
      end
      dest[c][:hits] += juan[:term_hits]
      dest[c][:docs] += 1
    end
  end

  def my_facet_creator(juan, dest)
    # ex: "龍樹(A001482);鳩摩羅什(A001583)"
    juan[:creators_with_id].split(';').each do |c|
      name, id = c.scan(/^(.*)\((.*)\)$/).first
      unless dest.key?(id)
        dest[id] = { creator_id: id, creator_name: name, hits: 0, docs: 0 }
      end
      dest[id][:hits] += juan[:term_hits]
      dest[id][:docs] += 1
    end
  end

  def my_facet_dynasty(juan, dest)
    d = juan[:time_dynasty]
    unless dest.key?(d)
      dest[d] = { dynasty: d, hits: 0, docs: 0 }
    end
    dest[d][:hits] += juan[:term_hits]
    dest[d][:docs] += 1
  end

  def my_facet_work(juan, dest)
    k = juan[:work]
    unless dest.key?(k)
      dest[k] = { work: k, title: juan[:title], hits: 0, docs: 0 }
    end
    dest[k][:hits] += juan[:term_hits]
    dest[k][:docs] += 1
  end

  def kwic_by_juan(r)
    t1 = Time.now
    base = Rails.application.config.kwic_base
    #se = Kwic3Helper::SearchEngine.new(base)
    se = KwicService.new(base)
    r[:results].each do |juan|
      #logger.debug "=== work: #{juan[:work]}, juan: #{juan[:juan]} ==="
      opts = {
        work: juan[:work],
        juan: juan[:juan].to_i,
        around: @around,
        mark: true,
        rows: 99999
      }
      juan[:kwics] = kwic_boolean(se, opts)
      #logger.debug "#{Time.now} kwic_boolean 完成"
      raise CbetaError.new(500), "kwic_boolean 回傳 nil" if juan[:kwics].nil?
      juan[:kwics][:results].sort_by! { |x| x['lb'] }
      juan[:term_hits] = juan[:kwics][:num_found]
    end
    r[:results].delete_if { |x| x[:kwics][:results].empty? }
    logger.debug "kwic_by_juan 花費時間： #{Time.now - t1}"
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

    q = @q.gsub(/[!\-]"[^"]+"/, '') # 去除 not 之後的關鍵字
    q.gsub!(/"/, '')
    keys = q.split

    keys.each do |k|
      t1 = Time.now
      h = se.search(k, opts)
      logger.debug "kwic search 花費時間: #{Time.now - t1}, work: #{opts[:work]}, juan: #{opts[:juan]}"
      num_found += h[:num_found]
      a += h[:results]
    end

    a.each do |h|
      h.delete('vol')
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
    if @mode == 'normal'
      @q.gsub!(/[\n\.\[\]\-\*　。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）—]/, '')
    else
      # 允許半形 '-'
      @q.gsub!(/[\n\.\[\]\*　。，、？！：；「」『』《》＜＞〈〉〔〕［］【】〖〗（）—]/, '')
    end
  end

  def set_filter
    @filter = ''
    set_filter_category
    set_filter_creator
    
    
    if params.key? :canon
      @filter += " AND canon='%s'" % params[:canon]
    end
    
    if params.key? :dynasty
      s = params[:dynasty]
      if s.include? ','
        a = s.split(',')
        a.map! { |x| "'#{x}'"}
        @filter += " AND dynasty IN (%s)" % a.join(',')
      else
        @filter += " AND dynasty='#{s}'"
      end
    end
    
    if params.key? :time
      s = params[:time]
      if s.include? '..'
        t1, t2 = s.split('..')
        @filter += " AND time_from<=#{t2} AND time_to>=#{t1}"
      else
        @filter += " AND time_from<=#{s} AND time_to>=#{s}"
      end
    end
    
    if params.key? :work
      @filter += " AND work='%s'" % params[:work]
    end
    
    if params.key? :works
      works = params[:works].split(',')
      works.map! { |x| %('#{x}')}
      @filter += " AND work IN (%s)" % works.join(',')
    end

    if params.key? :work_type
      t = params[:work_type]
      @filter += " AND work_type='#{t}'"
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
        a = []
        names.each do |name|
          a << Category.get_n_by_name(name).to_s
        end
        and_conditions << "(category_ids IN (%s))" % a.join(',')
      end
    end

    @filter += ' AND ' + and_conditions.join(' AND ')
  end
  
  # a,b+c,d 表示 (a OR b) AND (c OR d)
  def set_filter_creator
    return unless params.key? :creator
    and_conditions = []
    params[:creator].split('+').each do |exp|
      a = []
      exp.split(',').each do |c|
        a << c.sub(/^A0*(\d+)$/, '\1')
      end
      s = a.join(',')
      and_conditions << "creator_id IN (#{s})"
    end

    @filter += ' AND ' + and_conditions.join(' AND ')
  end

  def sphinx_search(fields, where, start, rows, order: nil, facet: nil)
    t1 = Time.now
    
    @select = %(
      SELECT #{fields}
      FROM #{@index} 
      WHERE #{where} #{order} 
      LIMIT #{start}, #{rows} 
      OPTION #{OPTION}
    ).gsub(/\s+/, " ").strip
    
    @select += " FACET #{facet}" unless facet.nil?
    results = @mysql_client.query(@select, symbolize_keys: true)
    hits = results.to_a
    return hits if @mode == 'group'
    
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
    
    if total_found == 0
      total_term_hits = 0
    else
      select2 = %(SELECT sum(weight()) as sum FROM #{@index} WHERE #{where} OPTION #{OPTION};)
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
    where = %{MATCH('"#{q}"')} + @filter
    fields = 'weight() as term_hits, work, juan'
    select = %(
      SELECT #{fields}
      FROM #{@index}
      WHERE #{where}
      LIMIT 0, #{MAX_JUAN}
      OPTION #{OPTION}
    ).gsub(/\s+/, " ").strip
    
    results = @mysql_client.query(select, symbolize_keys: true)
    results.to_a
  end

  def sphinx_mysql_connection
    Mysql2::Client.new(:host => 0, :port => 9306, encoding: 'utf8mb4')
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
    select += " LIMIT #{@opts[:start]}, #{@opts[:rows]} OPTION #{OPTION}"
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
      select2 = %(SELECT sum(weight()) as sum FROM #{@index} WHERE #{@where} OPTION #{OPTION};)
      r = @mysql_client.query(select2)
      term_hits = r.to_a[0]['sum']
    end

    return found, term_hits
  end

end
