module CbetaSearch
  # 把 Query 與 API 參數組成 Elasticsearch query body。
  #
  # filter 的語意完全對應舊 SearchController#set_filter，
  # 排序對應 SearchController#init_order。
  class ElasticQueryBuilder
    # _source 要回傳的欄位。content 全文已在 mapping 的 _source.excludes 排除。
    SOURCE_FIELDS = %w[
      canon canon_order category category_ids creator_id file vol work
      title byline creators creators_with_id dynasty
      time_from time_to juan juan_start juan_list work_type alt
    ].freeze

    # API 的 order 欄位 → ES 欄位。舊 API 可用的排序欄位見 static_pages/search.haml。
    SORT_FIELDS = {
      'canon' => 'canon_order',
      'canon_order' => 'canon_order',
      'category' => 'category',
      'file' => 'file',
      'vol' => 'vol',
      'work' => 'work',
      'juan' => 'juan',
      'work_type' => 'work_type',
      'dynasty' => 'dynasty',
      'time_dynasty' => 'dynasty',
      'time_from' => 'time_from',
      'time_to' => 'time_to',
      'title' => 'title.keyword',
      'byline' => 'byline.keyword',
      'creators' => 'creators.keyword',
      'creators_with_id' => 'creators_with_id.keyword'
    }.freeze

    # Manticore 對 time_from / time_to 會先以 has_time_from DESC 排序，
    # 讓「有年代」的排在「年代未知 (0)」之前。ES 用 script sort 表達同一件事。
    HAS_VALUE_SCRIPT = "doc['%s'].size() == 0 || doc['%s'].value == 0 ? 1 : 0".freeze

    # all_in_one 的預設排序
    DEFAULT_SORT = [
      { 'canon_order' => { 'order' => 'asc' } },
      { 'work' => { 'order' => 'asc' } },
      { 'juan' => { 'order' => 'asc' } }
    ].freeze

    # search / extended 無 order 參數時，Manticore 預設按 weight() 遞減
    SCORE_SORT = [{ '_score' => { 'order' => 'desc' } }].freeze

    # 排序值相同時的最後比較依據。
    # 舊版 Manticore 在平手時是回傳內部 doc id 的順序 (不可預期，例如同一部典籍的
    # 卷 3 會排在卷 1 前面)，這裡改成穩定且語意合理的順序，讓分頁結果可預期。
    TIEBREAKER = %w[canon_order work juan].freeze

    def initialize(referer_cn: false)
      @referer_cn = referer_cn
    end

    def search_body(query, params:, field:)
      {
        'query' => filtered_query(query, params:, field:),
        '_source' => SOURCE_FIELDS,
        'track_total_hits' => true
      }
    end

    def filtered_query(query, params:, field:)
      bool = { 'must' => [match_query(query, field:)] }
      filters = filters(params)
      bool['filter'] = filters if filters.any?
      must_not = filters_must_not(params)
      bool['must_not'] = must_not if must_not.any?

      { 'bool' => bool }
    end

    # 查詢主體 (不含 filter)
    def match_query(query, field:)
      case query.type
      when :phrase  then scored_phrase(field, query.phrase)
      when :bool    then bool_query(query, field)
      when :near    then near_intervals(field, query)
      when :exclude then exclude_intervals(field, query)
      else
        raise CbetaError.new(500), "未知的查詢類型：#{query.type}"
      end
    end

    def sort(params, default: DEFAULT_SORT)
      order = params[:order].to_s
      clauses =
        if order.blank?
          default
        else
          order.split(',').flat_map { |token| sort_clauses_for(token) }.presence || default
        end

      append_tiebreaker(clauses)
    end

    private

    def append_tiebreaker(clauses)
      used = clauses.flat_map(&:keys)
      missing = TIEBREAKER.reject { |field| used.include?(field) }
      return clauses if missing.empty?

      clauses + missing.map { |field| { field => { 'order' => 'asc' } } }
    end

    def match_phrase(field, phrase)
      { 'match_phrase' => { field => { 'query' => phrase } } }
    end

    # 會計分的詞組查詢: 把 match_phrase 包進 script_score，把 _score 除以 token 數。
    #
    # content 欄位掛的是 term_freq scripted similarity，
    # 因此 match_phrase 的 _score = 出現次數 × token 數 (Lucene 對 phrase 的每個
    # term 各執行一次 script 再相加)。除以 token 數之後 _score 就是出現次數本身，
    # 多個詞組相加時也不會被詞長加權 —— 與 Manticore ranker=wordcount 語意相同。
    #
    # 除數必須是 token 數而不是字元數: 中文一字一 token，但連續的拉丁字母
    # 是一個 token (見 TextIndex::TOKEN_PATTERN)，例如「Ānanda」是 1 個 token、
    # 「Pāli Text Society」是 3 個。
    #
    # 註: query 層級的 boost 對 scripted similarity 無效 (實測會被忽略)，
    #     所以必須用 script_score 而不是 boost。
    def scored_phrase(field, phrase)
      tokens = TextIndex.token_count(phrase)
      {
        'script_score' => {
          'query' => match_phrase(field, phrase),
          'script' => { 'source' => "_score / #{tokens}" }
        }
      }
    end

    # AND / OR / NOT。must_not 不計分，與 Manticore ranker=wordcount 一致。
    def bool_query(query, field)
      bool = {}
      must = query.must.map { |term| scored_phrase(field, term) }
      must += query.should_groups.map do |group|
        {
          'bool' => {
            'should' => group.map { |term| scored_phrase(field, term) },
            'minimum_should_match' => 1
          }
        }
      end
      bool['must'] = must if must.any?
      if query.must_not.any?
        bool['must_not'] = query.must_not.map { |term| match_phrase(field, term) }
      end

      { 'bool' => bool }
    end

    # intervals 的 match 預設 ordered: false、max_gaps: -1，
    # 多字詞必須明寫，否則「直心」會被拆成「直」「心」任意比對。
    def phrase_interval(text)
      { 'match' => { 'query' => text, 'ordered' => true, 'max_gaps' => 0 } }
    end

    # NEAR 鏈以左結合的巢狀 all_of 表達:
    #   "A" NEAR/7 "B" NEAR/3 "C" → all_of([all_of([A, B], 7), C], 3)
    # ES 只負責篩候選卷，實際 term_hits 與 KWIC 由 KwicService 逐卷計算，
    # 因此候選只要不漏 (允許輕微超集，例如兩詞區間重疊) 即可。
    def near_intervals(field, query)
      terms = query.near_terms
      distances = query.near_distances

      interval = phrase_interval(terms.first)
      terms.each_with_index do |term, i|
        next if i.zero?

        interval = {
          'all_of' => {
            'intervals' => [interval, phrase_interval(term)],
            'ordered' => false,
            'max_gaps' => distances[i - 1]
          }
        }
      end

      { 'intervals' => { field => interval } }
    end

    # 排除規則: phrase 的出現若被「完整排除字串」的出現包含，該出現不算。
    # 與 KwicService 的 negative_lookahead / negative_lookbehind 同語意。
    # (不能用 not_overlapping: 自重疊詞如「心心 -正心心」會誤殺相鄰的合法出現。)
    def exclude_intervals(field, query)
      excluded = "#{query.exclude_prefix}#{query.phrase}#{query.exclude_suffix}"
      {
        'intervals' => {
          field => {
            'match' => phrase_interval(query.phrase)['match'].merge(
              'filter' => { 'not_contained_by' => phrase_interval(excluded) }
            )
          }
        }
      }
    end

    def filters(params)
      [].tap do |f|
        append_terms(f, 'canon', params[:canon])
        append_terms(f, 'work', params[:works].presence || params[:work])
        append_terms(f, 'dynasty', params[:dynasty])
        append_terms(f, 'work_type', params[:work_type])
        append_category(f, params[:category])
        append_creator(f, params[:creator])
        append_time(f, params[:time])
      end
    end

    # *.cn 對太虛、印順 屏蔽 (見 config.cn_filter)
    def filters_must_not(_params)
      return [] unless @referer_cn

      [{ 'terms' => { 'canon' => Rails.configuration.cn_filter } }]
    end

    def append_terms(filters, field, value)
      return if value.blank?

      values = value.to_s.split(',').map(&:strip).reject(&:empty?)
      return if values.empty?

      filters << if values.one?
                   { 'term' => { field => values.first } }
                 else
                   { 'terms' => { field => values } }
                 end
    end

    # a,b+c,d 表示 (a OR b) AND (c OR d)
    def append_category(filters, value)
      return if value.blank?

      value.to_s.split('+').each do |exp|
        ids = exp.split(',').filter_map { |name| Category.get_n_by_name(name.strip) }
        next if ids.empty?

        filters << if ids.one?
                     { 'term' => { 'category_ids' => ids.first } }
                   else
                     { 'terms' => { 'category_ids' => ids } }
                   end
      end
    end

    # a,b+c,d 表示 (a OR b) AND (c OR d)。creator id 去掉 A 與前導零。
    def append_creator(filters, value)
      return if value.blank?

      value.to_s.split('+').each do |exp|
        ids = exp.split(',').filter_map do |c|
          i = c.strip.sub(/\AA0*(\d+)\z/, '\1').to_i
          i unless i.zero?
        end
        next if ids.empty?

        filters << { 'terms' => { 'creator_id' => ids } }
      end
    end

    def append_time(filters, value)
      return if value.blank?

      if value.to_s.include?('..')
        from, to = value.to_s.split('..', 2).map(&:to_i)
      else
        from = to = value.to_i
      end
      filters << { 'range' => { 'time_from' => { 'lte' => to } } }
      filters << { 'range' => { 'time_to' => { 'gte' => from } } }
    end

    def sort_clauses_for(token)
      field, direction = parse_order_token(token)

      # term_hits: term_freq similarity 下 _score = 出現次數 × 詞長，
      # 同一查詢的詞長固定，因此以 _score 排序等價於以 term_hits 排序。
      return [{ '_score' => { 'order' => direction == 'asc' ? 'asc' : 'desc' } }] if field == 'term_hits'

      es_field = SORT_FIELDS[field]
      return [] if es_field.blank?

      clauses = []
      if %w[time_from time_to].include?(field)
        clauses << {
          '_script' => {
            'type' => 'number',
            'script' => { 'source' => format(HAS_VALUE_SCRIPT, es_field, es_field) },
            'order' => 'asc'
          }
        }
      end
      clauses << { es_field => { 'order' => direction } }
      clauses
    end

    def parse_order_token(token)
      token = token.to_s.strip
      if token.end_with?('-')
        [token.delete_suffix('-'), 'desc']
      elsif token.end_with?('+')
        [token.delete_suffix('+'), 'asc']
      else
        # 舊行為: term_hits 預設遞減，其他遞增
        [token, token == 'term_hits' ? 'desc' : 'asc']
      end
    end
  end
end
