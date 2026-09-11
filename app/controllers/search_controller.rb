# all_in_one
#   Exclude X -Y
#     1. 先呼叫 Elasticsearch 取得全部符合 X 的卷數
#     2. 每一卷呼叫 KWIC 過濾 -Y
#        2.1 取得本卷符合 X 的位置
#        2.2 讀取前後文，過濾 -Y
#     3. 計算總筆數、Facet

require 'csv'
require 'open3'

class SearchController < ApplicationController
  include ApiKeyAuthentication

  # search/similar 第一階段 (Elasticsearch) 取回的候選筆數上限，可用 k 參數覆寫。
  #
  # 5.2.0 由 500 調高為 2000: 符合 quorum 的區塊動輒十萬筆，只有 top k 會進
  # Smith-Waterman，因此「取哪 k 筆」幾乎決定了最終結果。Manticore 的
  # proximity_bm25 把詞的相鄰程度算進分數，Lucene 的 BM25 不會，真正的相似句
  # 常掉到 500 名之外 —— 實測 6 個範例查詢，k=500 只涵蓋 Manticore 結果的 52%，
  # k=2000 涵蓋 76% 且總筆數還多一些。
  #
  # 代價是延遲: 第二階段的 Smith-Waterman 是 Ruby 單執行緒、成本與 k 成正比。
  # staging 實測 k=500 是 0.70 秒、k=2000 是 2.24 秒 (舊版 Manticore 0.79 秒)，
  # 2026-09-10 與主管確認取結果完整度、接受這個延遲。
  # 本機 macOS 量出來只有 1.1 秒 —— 這個數字會低估，要以 server 為準。
  # 詳見 doc/elasticsearch-migration.md 的第三期實作結果。
  SIMILAR_K = 2000
  # search/similar 第二階段 (Smith-Waterman) 的最低分數，可用 score_min 參數覆寫。
  SCORE_MIN = 16

  before_action :init
  rescue_from Exception, with: :error_handler

  # Elasticsearch 相關錯誤回 502，且不回傳 backtrace（那會洩漏伺服器路徑），
  # 完整錯誤只寫進 log。
  # 必須註冊在 rescue_from Exception 之後: Rails 是由後往前找第一個相符的 handler。
  rescue_from Elastic::Transport::Transport::Error,
              Elasticsearch::UnsupportedProductError,
              Faraday::Error,
              with: :elasticsearch_error_handler

  def initialize
    log_debug "SearchController initialize"
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
  rescue Elastic::Transport::Transport::Error, Elasticsearch::UnsupportedProductError, Faraday::Error
    # 交給 elasticsearch_error_handler 統一處理（回 502、不回 backtrace）。
    # 必須放在下面兩個 rescue 之前，否則會被它們攔下來變成 500 加 backtrace。
    raise
  rescue CbetaError => e
    r = { error: { code: e.code, message: $!, backtrace: e.backtrace } }
    my_render(r)
  rescue => e
    r = { 
      error: { code: 500, message: $!, backtrace: e.backtrace } 
    }
    my_render(r)
  end

  def index
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end

    # 無 order 參數時沿用舊行為: 按關鍵詞出現次數遞減
    my_render es_search(default_sort: CbetaSearch::ElasticQueryBuilder::SCORE_SORT)
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

  # 目前 config/routes.rb 沒有對應的 route
  def test
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end

    my_render es_search(default_sort: CbetaSearch::ElasticQueryBuilder::SCORE_SORT)
  end

  # 與 index 的差別只在說明文件: 查詢語法由 CbetaSearch::QueryParser 統一解析，
  # 因此兩個 endpoint 的行為相同。
  def extended
    @mode = 'extend'
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end

    my_render es_search(default_sort: CbetaSearch::ElasticQueryBuilder::SCORE_SORT)
  end

  def notes
    log_debug "action notes"
    @mode = 'extend'
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end

    r = es_search(index: CbetaSearch::NotesIndex)

    if params[:facet] == '1'
      # key 的順序與舊版一致
      r['facet'] = %w[category creator dynasty work canon]
                   .to_h { |f| [f, es_facet(f, index: CbetaSearch::NotesIndex)] }
    end

    notes_highlight(r)
    my_render r
  end

  def facet
    @mode = 'extend'
    remove_puncs_from_query

    raise CbetaError.new(400), "缺少 q 參數" if @q.empty?

    r =
      if params.key? :facet_by
        es_facet(params[:facet_by])
      else
        %w[canon category creator dynasty work].to_h { |f| [f, es_facet(f)] }
      end

    my_render r
  end
  
  # 目前 config/routes.rb 沒有對應的 route
  def fuzzy
    remove_puncs_from_query

    if @q.empty?
      my_render(empty_result)
      return
    end

    my_render es_search(default_sort: CbetaSearch::ElasticQueryBuilder::SCORE_SORT)
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
        {
          time: Time.now - t1,
          q: @q,
          hits: es_service.hit_count(es_query, params: es_params, field: @text_field)
        }
      end
    my_render r
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
    # 舊版是 Manticore 的 quorum: MATCH('"觀 無 量 壽 經"/3')，至少 3 個字符合。
    query = CbetaSearch::Query.new(
      type: :quorum, raw: @q, phrase: @q,
      quorum: CbetaSearch::TitlesIndex::QUORUM_THRESHOLD
    )
    r = es_service(CbetaSearch::TitlesIndex).search(
      query, params: es_params, start: @start, rows: @rows, count_hits: false
    )

    r[:results].each do |h|
      h[:highlight] = mark_title(h[:content], @q)
      w = Work.find_by(n: h[:work])
      next if w.nil?

      h[:byline] = w.byline
      h[:juan] = w.juan
      h[:creators_with_id] = w.creators_with_id
      h[:time_dynasty] = w.time_dynasty
      h[:time_from] = w.time_from
      h[:time_to] = w.time_to
    end

    r.delete(:cache_key)
    r[:time] = Time.now - t1
    my_render r
  end

  private

  # ===== Elasticsearch =====
  #
  # text / notes / titles / chunks 四個 index 全部走 Elasticsearch。
  # 見 doc/elasticsearch-migration.md

  # 這個 action 主要查哪一個 Elasticsearch index。
  def es_index
    case action_name
    when 'notes'   then CbetaSearch::NotesIndex
    when 'title'   then CbetaSearch::TitlesIndex
    when 'similar' then CbetaSearch::ChunksIndex
    when 'variants'
      params[:scope] == 'title' ? CbetaSearch::TitlesIndex : CbetaSearch::TextIndex
    else CbetaSearch::TextIndex
    end
  end

  # 依 index 各自快取一個 SearchService: exist_in_cbeta 一次要查三個 index。
  def es_service(index = es_index)
    @es_services ||= {}
    @es_services[index] ||= CbetaSearch::SearchService.new(referer_cn: @referer_cn, index:)
  end

  def es_query
    @es_query ||= CbetaSearch::QueryParser.new.parse(@q)
  end

  # 傳給 CbetaSearch::ElasticQueryBuilder 的參數 (filter 與排序)。
  # 直接取值而不用 params.permit: 其餘參數 (q / start / rows / fields …) 由
  # controller 自己處理，若走 permit 會被當成 unpermitted parameters。
  ES_PARAM_KEYS = %i[canon work works category creator dynasty time work_type order].freeze

  def es_params
    @es_params ||= ES_PARAM_KEYS.to_h { |key| [key, params[key]] }.compact
  end

  # 對應舊的 sphinx_search（已移除）
  def es_search(index: es_index, default_sort: nil, count_hits: true)
    r = es_service(index).search(
      es_query,
      params: es_params, start: @start, rows: @rows,
      field: @text_field, default_sort:, count_hits:
    )
    r.delete(:total_term_hits) if r.key?(:total_term_hits) && r[:total_term_hits].nil?
    filter_es_fields!(r[:results])
    r
  end

  # 依 fields 參數過濾回傳欄位 (舊版是在 SQL 的 select list 做這件事)。
  # kwics 由 all_in_one 另外加上，其保留與否見 kwic_by_juan。
  def filter_es_fields!(rows)
    return rows if rows.blank? || @field_keys.blank?

    keys = @field_keys.map(&:to_sym)
    rows.each { |row| row.select! { |k, _| keys.include?(k) || k == :kwics } }
    rows
  end

  # 對應舊的 facet_by_sphinx（已移除）: Elasticsearch 算出 docs / hits，
  # 這裡補上名稱與排序。
  def es_facet(facet_by, index: es_index)
    # NEAR / Exclude 走 intervals，_score 不是出現次數，加總得到的 hits 沒有意義。
    # 舊版是把整串當詞組 (搜不到、回空陣列)，這裡改成明確報錯。
    unless es_query.es_countable?
      raise CbetaError.new(400), 'facet 不支援 NEAR 與 Exclude 語法'
    end

    read_dynasty_order if facet_by == 'dynasty'
    rows = es_service(index).facet(es_query, params: es_params, facet_by:, field: @text_field)
    decorate_facet!(facet_by, rows)
  end

  def decorate_facet!(facet_by, rows)
    case facet_by
    when 'canon'
      rows.each do |row|
        c = Canon.find_by id2: row[:canon]
        row[:canon_name] = c.name unless c.nil?
      end
    when 'category'
      fn = Rails.root.join('data-static', 'categories.json')
      categories = JSON.parse(File.read(fn))
      rows.each { |row| row['category_name'] = categories[row[:category_id].to_s] }
    when 'creator'
      rows.each do |row|
        row[:creator_id] = "A%06d" % row[:creator_id]
        person = Person.find_by(id2: row[:creator_id])
        if person.nil?
          Rails.logger.debug "Person model 無此 ID: #{row[:creator_id]}"
        else
          row[:creator_name] = person.name
        end
      end
    when 'dynasty'
      rows.sort_by! { |x| @dynasty_order.fetch(x[:dynasty], 999) }
    when 'work'
      rows.each do |row|
        w = Work.find_by n: row[:work]
        row['title'] = w.title unless w.nil?
      end
    end
    rows
  end

  def add_work_info(rows)
    rows.each do |row|
      w = Work.find_by n: row[:work]
      next if w.nil?
      
      info = w.to_hash
      info.delete :juan # 要保留搜尋結果回傳的卷數
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
  #   all_in_one_fetch
  #     CbetaSearch::SearchService#search / #all_candidates / #exclude_candidates
  #   es_facet_all
  #   kwic_by_juan
  #     kwic_boolean
  #       KwicService::search_near
  #       kwic_boolean_exclude
  #         KwicSearvice::search_juan
  def all_in_one_sub
    @canon_name = {}
    @exclude = nil
    query = es_query

    # NEAR 與 Exclude 的 term_hits、KWIC 都要由 KwicService 逐卷計算
    # (Elasticsearch 的 intervals 允許兩詞區間重疊，KWIC 不允許)，
    # 因此這兩種查詢先取回全部符合的卷，過濾完才分頁。
    two_phase = %i[near exclude].include?(query.type)

    case query.type
    when :near
      @mode = 'near'
    when :exclude
      @mode = 'exclude'
      @exclude = "#{query.exclude_prefix}#{query.phrase}#{query.exclude_suffix}"
      @q = query.phrase # kwic_boolean_exclude 需要「不含排除條件」的查詢詞
    end
    @q_orig = @q

    r = all_in_one_fetch(query)

    # NEAR 跟 Exclude 的 facet 要等 KWIC 過濾完，改由 my_facet 依結果計算
    if params[:facet] == '1' && !two_phase
      r['facet'] = {}
      es_facet_all(r['facet'])
    end

    if query.type == :near
      # 呼叫 KWIC 過濾 NEAR, 並取得所有出處、行號
      kwic_by_juan(r)
      r[:num_found] = r[:results].size
      r[:total_term_hits] = r[:results].sum { it[:term_hits] }
    end

    if two_phase
      r[:facet] = my_facet(r[:results]) if @facet == 1

      @start = params.key?(:start) ? params[:start].to_i : 0
      @rows  = params.key?(:rows)  ? params[:rows].to_i  : 20
      r[:results] = r[:results][@start, @rows] || []
    end

    if params[:fields].nil? or params[:fields].include?('kwic')
      kwic_by_juan(r) unless query.type == :near
    end

    filter_es_fields!(r[:results]) if two_phase

    if r.key?(:results)
      log_debug "results size: #{r[:results].size}"
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
      log_debug "#{__LINE__} r 沒有 results"
    end

    r
  end

  # all_in_one 的第一階段: 取回符合的卷。
  # NEAR / Exclude 不分頁 (要先過濾), 其餘直接取當頁。
  def all_in_one_fetch(query)
    case query.type
    when :exclude
      rows = es_service.exclude_candidates(query, params: es_params, field: @text_field)
      {
        query_string: query.raw,
        num_found: rows.size,
        total_term_hits: rows.sum { it[:term_hits] },
        cache_key: nil,
        results: rows
      }
    when :near
      rows = es_service.all_candidates(query, params: es_params, field: @text_field)
      {
        query_string: query.raw,
        num_found: rows.size,
        total_term_hits: nil, # KWIC 過濾後才算得出來，這裡先佔位以維持欄位順序
        cache_key: nil,
        results: rows
      }
    else
      es_search
    end
  end

  def es_facet_all(dest)
    %w[category creator dynasty work canon].each { |f| dest[f] = es_facet(f) }
  end
  
  def empty_result
    {
      query_string: @q,
      num_found: 0,
      total_term_hits: 0,
      results: []
    }
  end

  # 這個字串在 CBETA 全文、註解或經名裡出現過嗎? (variants 用)
  # 三個 index 都走 Elasticsearch，任一個命中就算存在。
  def exist_in_cbeta(q)
    log_debug "exist_in_cbeta, q: #{q}"
    query = es_phrase_query(q)

    return true if es_service(CbetaSearch::TextIndex).exist?(query, params: {})
    return true if es_service(CbetaSearch::NotesIndex).exist?(query, params: {})

    # title 最長 57, query 太長就不必搜了
    return false if q.size >= 58

    es_service(CbetaSearch::TitlesIndex).exist?(query, params: {})
  end

  # 單純詞組查詢 (variants / exist_in_cbeta 用): 不經 QueryParser，
  # 因為異體字展開後的字串可能含雙引號等字元，不該被當成查詢語法。
  def es_phrase_query(phrase)
    CbetaSearch::Query.new(type: :phrase, raw: phrase, phrase: phrase.downcase)
  end

  # variants 的計數。scope=title 查 titles index 的 freq sub-field
  # (主欄位掛的是 BM25，算不出出現次數)，其餘查 text index。
  def variants_hit_count(phrase)
    if params[:scope] == 'title'
      es_service(CbetaSearch::TitlesIndex).hit_count(
        es_phrase_query(phrase), params: es_params,
        field: CbetaSearch::TitlesIndex::FREQ_SUBFIELD
      )
    else
      es_service(CbetaSearch::TextIndex).hit_count(es_phrase_query(phrase), params: es_params)
    end
  end

  def init
    @referer_cn = referer_cn?

    unless params.key? :q
      render plain: '缺少必要參數：q'
      return false
    end
    
    @q = Gaiji.replace_zzs_with_pua(params[:q]) # 將 組字式 取代為 Unicode PUA
    if @q.blank?
      render plain: 'q 參數不能是空的'
      return false
    end

    # 限制查詢字串長度（組字式已轉為 PUA，以實際字數計算），
    # 避免過長的 query 造成全文檢索後端負擔。
    raise CbetaError.new(400), query_length_error if query_too_long?(@q)

    @mode = 'normal'
    @use_cache = params.key?(:cache) ? (params[:cache]=='1') : true
    @start  = params.key?(:start)  ? params[:start].to_i  : 0
    @rows   = params.key?(:rows)   ? params[:rows].to_i   : 20
    @around = params.key?(:around) ? params[:around].to_i : 10
    @facet  = params.key?(:facet)  ? params[:facet].to_i  : 0
    @inline_note = params.key?(:note) ? params[:note]=='1' : true
    @score_min = params.key?(:score_min) ? params[:score_min].to_i : SCORE_MIN
    # note=0 (不含夾注) 只有 text index 有對應欄位; notes / titles index 沒有。
    @text_field =
      if es_index == CbetaSearch::TextIndex && !@inline_note
        'content_without_notes'
      else
        es_index.default_field
      end

    case action_name
    when 'similar'
      @similar_k = params.key?(:k) ? params[:k].to_i : SIMILAR_K
      @gain  = params.key?(:gain)  ? params[:gain].to_i : 2
      @penalty  = params.key?(:penalty)  ? params[:penalty].to_i : -1
      raise CbetaError.new(400), 'k 參數 必須 > 0' if @similar_k < 1
      raise CbetaError.new(400), 'gain 參數 必須 >= 0' if @gain < 0
      raise CbetaError.new(400), 'penalty 參數 必須 <= 0' if @penalty > 0
    when 'notes', 'title'
      # 回傳欄位固定 (見各自的 index class ROW_FIELDS)，不吃 fields 參數
    else
      init_fields
    end
  end

  # 回傳欄位的預設清單與順序 (text index 用)
  FIELD_KEYS = %w[
    id term_hits canon category file work juan title byline creators
    creators_with_id time_dynasty time_from time_to juan_list
  ].freeze

  def init_fields
    @field_keys =
      if params.key?(:fields)
        FIELD_KEYS & params[:fields].split(',')
      else
        FIELD_KEYS
      end
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
      log_debug "kwic_by_juan, work: #{juan[:work]}, juan: #{juan[:juan]}"
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

  def notes_highlight(r)
    q1 = params[:q].sub(/\A"(.*)"\z/, '\1') # 未去標點的 Query String

    # 允許標點差異的 regular expression
    q2 = @q.sub(/\A"(.*)"\z/, '\1')
    s = q2.chars.join("[【】，〔－〕＊。]*")
    log_debug "notes_highlight, exp: #{s}"
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
    log_debug "notes_inline_around, highlight: #{h[:highlight]}"
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
    log_debug "similar_sub"
    remove_puncs_from_query
    @canon_name = {}

    # 第一階段: Elasticsearch 用 quorum (一半的字命中) + BM25 相關度取 top k 候選。
    # 舊版是 Manticore 的 MATCH('"<q>"/0.5') + ranker=proximity_bm25。
    query = CbetaSearch::Query.new(
      type: :quorum, raw: @q, phrase: @q,
      quorum: CbetaSearch::ChunksIndex::QUORUM_RATIO
    )
    r = es_service(CbetaSearch::ChunksIndex).search(
      query, params: es_params, start: 0, rows: @similar_k,
      default_sort: CbetaSearch::ElasticQueryBuilder::SCORE_SORT,
      count_hits: false, track_total_hits: false
    )
    hits = r[:results]

    # 第二階段: Smith-Waterman 逐筆比對、去重，再依 score 排序。
    log_debug "begin similar_smith_waterman"
    similar_smith_waterman(hits)
    log_debug "begin similar_rm_duplicate"
    similar_rm_duplicate(hits)
    hits.sort_by! { |x| -x[:score] }

    # position_in_juan 只是 similar_smith_waterman 的判斷依據，不對外回傳。
    hits.each { it.delete(:position_in_juan) }

    r[:num_found] = hits.size

    if params[:facet] == '1'
      r[:facet] = my_facet(r[:results])
    end

    r
  end

  def similar_smith_waterman(hits)
    log_debug "begin similar_smith_waterman, hits size: #{hits.size}, gain: #{@gain}, penalty: #{@penalty}"

    cs = CbetaString.new(allow_digit: true, allow_space: false)
    i = 0
    pruned = 0
    while i < hits.size
      node = hits[i]
      text = cs.remove_puncs(node[:content])
      #text = node[:content]
      
      # 去除完全符合的
      if text.include?(@q)
        hits.delete_at(i)
        next
      end

      # 分數上界不到門檻的，連矩陣都不必建。
      # 候選是 quorum 50% 挑出來的 (一半的字命中即可)，但要通過 score_min
      # 需要更多字對得上，因此候選池裡本來就有一批是「可證明拿不到分數」的。
      # 剪掉的都是下面 sw.score < @score_min 本來就會淘汰的，結果不變。
      if SmithWaterman.max_score(@q, text, gain: @gain) < @score_min
        pruned += 1
        hits.delete_at(i)
        next
      end

      sw = SmithWaterman.new(@q, text, gain: @gain, penalty: @penalty)
      if sw.score! < @score_min
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
    log_debug "end similar_smith_waterman, 上界剪枝 #{pruned} 筆"
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

  # 根據異體字表，回傳各種可能異體字串及搜尋結果筆數
  # 效率測試：
  #   * 無上正等正覺
  #   * 大比丘三千威儀
  #   * 阿耨多羅三藐三菩提
  def variants_sub
    log_debug "variants_sub, scope: #{params[:scope]}"
    t1 = Time.now
    remove_puncs_from_query
    log_debug "variants_sub, q: #{@q}"
    q_ary = get_query_variants(@q)
        
    results = []
    q_ary.each do |q|
      next if q == @q

      i = variants_hit_count(q)
      results << { q: q, hits: i } unless i.zero?
    end
    
    {
      time: Time.now - t1,
      num_found: results.size,
      cache_key: nil,
      possibility: q_ary.size,
      results: results
    }
  end

  def get_query_variants(q)
    log_debug "get_query_variants, q: #{q}"
    remove_puncs_from_query
    vars = []
    q = q.gsub('菩薩', '𦬇')
    q.each_char do |c|
      if c == '𦬇'
        vars << ['𦬇', '菩薩']
      else
        v = Variant.find_by(k: c)
        vars << Set[c]
        unless v.nil?
          vars[-1].merge(v.vars.split(','))
        end
        vars[-1] = vars[-1].to_a
      end
    end
    return expand_vars_array(vars, true)
  end

  # @param vars [Array] example: [["又", "叹"], ["道", "噵", "衜", "衟", "𨕥"], ["未"]]
  def expand_vars_array(vars, chk_exist)
    log_debug "expand_vars_array, vars: #{vars}, chk_exist: #{chk_exist}"
    return [] if vars.blank?

    r = [""]
    until vars.empty?
      a1 = r
      a2 = vars.shift
      r = []
      a1.each do |s1|
        a2.each do |s2|
          s = s1 + s2
          r << s if exist_in_cbeta(s)
        end
      end
      break if r.empty? # 已經搜不到了，就不必再往下找了
    end

    log_debug "#{__LINE__} expand_vars_array result: %s" % r.inspect
    r
  end

  def elasticsearch_error_handler(e)
    logger.fatal "Elasticsearch 錯誤 (#{e.class}): #{e.message}"
    logger.fatal "environment: #{Rails.env}, url: #{Rails.configuration.x.elasticsearch.url}"
    logger.fatal e.backtrace.first(5).join("\n") unless e.backtrace.nil?

    r = { error: { code: 502, message: elasticsearch_error_message(e) } }
    if params.key?('callback')
      render json: r, callback: params['callback'], content_type: 'application/javascript', status: 502
    else
      render json: r, status: 502
    end
  end

  # index 或 alias 不存在是最常見的部署疏漏（忘了 elastic:rebuild 或 elastic:promote），
  # 給一個可以照著處理的訊息；其餘狀況只說服務不可用，細節留在 log。
  # alias 取這個 action 主要查的 index（見 es_index），才不會三個 index 都報同一個名字。
  def elasticsearch_error_message(e)
    if e.is_a?(Elastic::Transport::Transport::Errors::NotFound)
      "全文檢索索引尚未建立：#{es_index.index_alias}"
    else
      '全文檢索服務暫時無法使用'
    end
  end

  def error_handler(e)
    logger.fatal $!
    logger.fatal "environment: #{Rails.env}"
    logger.fatal e.backtrace.join("\n")

    if e.is_a?(CbetaError) && e.code == 504
      r = { error: { code: 504, message: e.message } }
      if params.key?('callback')
        render json: r, callback: params['callback'], content_type: "application/javascript", status: 504
      else
        render json: r, status: 504
      end
      return
    end

    r = empty_result
    r[:error] = e.message
    r[:backtrace] = e.backtrace
    my_render r
  end
end
