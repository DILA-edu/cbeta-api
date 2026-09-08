module CbetaSearch
  # Elasticsearch 版的 text index 搜尋，取代舊 SearchController 的 sphinx_* 方法。
  #
  # term_hits 的來源：
  #   * phrase / bool 查詢：由 Elasticsearch 的 _score 直接還原。
  #     每個 match_phrase 都設 boost = 1 / 詞長，配合 term_freq scripted similarity
  #     (_score = 出現次數 × 詞長) 之後，_score 恰好等於出現次數，
  #     與 Manticore ranker=wordcount 的語意相同。
  #   * NEAR / Exclude 查詢：intervals 的 _score 不是出現次數，
  #     由呼叫端 (SearchController#kwic_by_juan) 用 KwicService 逐卷計算。
  class SearchService
    # facet 筆數上限，對應舊 SearchController::FACET_MAX
    FACET_MAX = 10_000

    # 取全部候選卷時的單頁筆數 (all_in_one 的 NEAR / Exclude 用)
    SCROLL_BATCH_SIZE = 5_000

    # scripted_metric: 加總命中文件的 _score。boost 已把 _score 正規化成出現次數，
    # 因此總和即 total_term_hits。ES 的 aggregation 無法直接 sum(_score)，
    # 只有 scripted_metric 的 map_script 拿得到 _score。
    SUM_SCORE_AGG = {
      'scripted_metric' => {
        'init_script' => 'state.sum = 0.0',
        'map_script' => 'state.sum += _score',
        'combine_script' => 'return state.sum',
        'reduce_script' => 'double s = 0; for (a in states) { s += a } return s'
      }
    }.freeze

    attr_reader :client, :index

    def initialize(referer_cn: false, client: ElasticClient.build)
      @client = client
      @builder = ElasticQueryBuilder.new(referer_cn:)
      @index = Rails.configuration.x.elasticsearch.index_alias
    end

    # 對應舊的 sphinx_search。
    # 回傳 { query_string:, time:, num_found:, total_term_hits:, cache_key:, results: }
    # results 各筆為 symbol key 的 Hash，欄位與舊 Manticore 回傳一致。
    def search(query, params:, start: 0, rows: 20, field: 'content', default_sort: nil, count_hits: true)
      t1 = Time.now
      validate_window!(start, rows)

      # Exclude 的 term_hits 要靠「主要詞組次數 − 排除字串次數」逐卷相減才算得出來，
      # 沒辦法只看當頁，因此走另一條路徑 (與 all_in_one 相同的算法與結果)。
      return search_exclude(query, params:, start:, rows:, field:, default_sort:, t1:) if query.type == :exclude
      body = @builder.search_body(query, params:, field:)
      body['from'] = start
      body['size'] = rows
      body['sort'] = @builder.sort(params, default: default_sort || ElasticQueryBuilder::DEFAULT_SORT)
      body['track_scores'] = true

      response = client.search(index:, body:)
      rows = response.dig('hits', 'hits').map { |hit| row_from_hit(hit, query) }

      # total_term_hits 必須另發一次 size: 0 的查詢，不能和取當頁結果的查詢合併。
      # 原因: 取當頁 (size > 0) 時 Lucene 會做 top-k 動態剪枝，沒有機會進入
      # top-k 的文件不會被精確計分，同一個 request 裡的 aggregation 因此拿到
      # 偏低的 _score 總和 (實測「波羅蜜」合併查詢得 59262，正確值 111691)。
      # 舊版 Manticore 也是分成 SELECT 與 SELECT SUM(weight()) 兩道 SQL。
      # NEAR / Exclude 的 _score 不是出現次數，交由呼叫端以 KwicService 計算。
      total_term_hits = hit_count(query, params:, field:) if count_hits && query.es_countable?

      # key 的順序刻意與舊 Manticore 版一致 (不含只有除錯用的 SQL 欄位)
      result = {
        query_string: query.raw,
        time: Time.now - t1,
        num_found: response.dig('hits', 'total', 'value').to_i
      }
      result[:total_term_hits] = total_term_hits unless total_term_hits.nil?
      result[:cache_key] = nil
      result[:results] = rows
      result
    end

    # 取出所有符合的卷 (不分頁)，供 all_in_one 的 NEAR / Exclude 後處理使用。
    # 舊版是 LIMIT 0, 99999; ES 改用 search_after 逐批取回，沒有筆數上限。
    def all_candidates(query, params:, field: 'content', default_sort: nil)
      body = @builder.search_body(query, params:, field:)
      body['size'] = SCROLL_BATCH_SIZE
      body['track_scores'] = true
      sort = @builder.sort(params, default: default_sort || ElasticQueryBuilder::DEFAULT_SORT)
      # search_after 需要能唯一決定順序的 tiebreaker
      body['sort'] = sort + [{ '_doc' => { 'order' => 'asc' } }]

      rows = []
      search_after = nil
      loop do
        body['search_after'] = search_after if search_after
        response = client.search(index:, body:)
        hits = response.dig('hits', 'hits') || []
        break if hits.empty?

        hits.each { |hit| rows << row_from_hit(hit, query) }
        break if hits.size < SCROLL_BATCH_SIZE

        search_after = hits.last['sort']
      end
      rows
    end

    # Exclude 查詢的候選卷。
    # 先取主要詞組的全部符合卷 (term_hits = 該詞組出現次數)，再逐卷減去
    # 「完整排除字串」的出現次數，term_hits <= 0 的卷不算符合 ——
    # 與舊 SearchController#exclude_by_sphinx 完全相同的算法，
    # 因此 num_found 與 total_term_hits 都與 Manticore 版一致。
    def exclude_candidates(query, params:, field: 'content', default_sort: nil)
      excluded = "#{query.exclude_prefix}#{query.phrase}#{query.exclude_suffix}"
      base = Query.new(type: :phrase, raw: query.raw, phrase: query.phrase)
      minus = Query.new(type: :phrase, raw: excluded, phrase: excluded)

      subtract = simple_search(minus, params:, field:)
                 .to_h { |row| [[row[:work], row[:juan]], row[:term_hits]] }

      all_candidates(base, params:, field:, default_sort:).filter_map do |row|
        hits = row[:term_hits] - subtract.fetch([row[:work], row[:juan]], 0)
        row.merge(term_hits: hits) if hits.positive?
      end
    end

    # 對應舊的 sphinx_search_simple: 只取 work / juan / term_hits
    def simple_search(query, params:, field: 'content')
      body = @builder.search_body(query, params:, field:)
      body['_source'] = %w[work juan]
      body['size'] = SCROLL_BATCH_SIZE
      body['track_scores'] = true
      body['sort'] = [{ '_doc' => { 'order' => 'asc' } }]

      rows = []
      search_after = nil
      loop do
        body['search_after'] = search_after if search_after
        response = client.search(index:, body:)
        hits = response.dig('hits', 'hits') || []
        break if hits.empty?

        hits.each do |hit|
          source = hit['_source']
          rows << {
            term_hits: term_hits_from_score(hit['_score']),
            work: source['work'],
            juan: source['juan']
          }
        end
        break if hits.size < SCROLL_BATCH_SIZE

        search_after = hits.last['sort']
      end
      rows
    end

    # 對應舊的 get_hit_count: 只回傳關鍵詞出現總次數
    def hit_count(query, params:, field: 'content')
      return 0 unless query.es_countable?

      body = @builder.search_body(query, params:, field:)
      body['size'] = 0
      body['aggs'] = { 'total_term_hits' => SUM_SCORE_AGG }
      response = client.search(index:, body:)
      response.dig('aggregations', 'total_term_hits', 'value').to_f.round
    end

    # 對應舊的 exist_in_index: 只問「有沒有」，不算次數
    def exist?(query, params: {}, field: 'content')
      body = @builder.search_body(query, params:, field:)
      body['size'] = 0
      body['terminate_after'] = 1
      body['track_total_hits'] = 1
      response = client.search(index:, body:)
      response.dig('hits', 'total', 'value').to_i.positive?
    end

    # 對應舊的 facet_by_sphinx。
    # 回傳 [{ <field> => 值, docs: 文件數, hits: 出現次數 }, ...]，依 hits 遞減。
    # 舊版用 Manticore 的 GROUPBY() + SUM(weight())，ES 改用 terms aggregation
    # 搭配 scripted_metric 子 aggregation。
    def facet(query, params:, facet_by:, field: 'content')
      es_field, key = facet_field_and_key(facet_by)

      body = @builder.search_body(query, params:, field:)
      body['size'] = 0
      body['aggs'] = {
        'facet' => {
          'terms' => { 'field' => es_field, 'size' => FACET_MAX },
          'aggs' => { 'hits' => SUM_SCORE_AGG }
        }
      }

      response = client.search(index:, body:)
      buckets = response.dig('aggregations', 'facet', 'buckets') || []
      rows = buckets.map do |bucket|
        {
          key => bucket['key'],
          docs: bucket['doc_count'],
          hits: bucket.dig('hits', 'value').to_f.round
        }
      end
      rows.sort_by! { |row| -row[:hits] }
      rows
    end

    private

    # Exclude 查詢: 取全部候選、逐卷相減，再取當頁。
    # 與 all_in_one 走同一個 exclude_candidates，所以兩個 endpoint 的數字一致。
    def search_exclude(query, params:, start:, rows:, field:, default_sort:, t1:)
      candidates = exclude_candidates(query, params:, field:, default_sort:)
      page = candidates[start, rows] || []

      {
        query_string: query.raw,
        time: Time.now - t1,
        num_found: candidates.size,
        total_term_hits: candidates.sum { it[:term_hits] },
        cache_key: nil,
        results: page
      }
    end

    # Elasticsearch 的 from + size 有 index.max_result_window 上限
    # (見 TextIndex::MAX_RESULT_WINDOW)，超過會被 ES 拒絕。
    # 舊版是由 estimate_max_matches 算出 max_matches 再擋，這裡直接擋在上限。
    def validate_window!(start, rows)
      window = start.to_i + rows.to_i
      return if window <= TextIndex::MAX_RESULT_WINDOW

      raise CbetaError.new(400),
            "start 參數超出範圍: #{start}, start + rows 不得超過 #{TextIndex::MAX_RESULT_WINDOW}"
    end

    # facet 名稱 → [ES 欄位, 回傳的 key]。與舊 facet_by_sphinx 的欄位對應一致。
    def facet_field_and_key(facet_by)
      case facet_by.to_s
      when 'category' then ['category_ids', :category_id]
      when 'creator'  then ['creator_id',   :creator_id]
      when 'canon'    then ['canon',        :canon]
      when 'dynasty'  then ['dynasty',      :dynasty]
      when 'work'     then ['work',         :work]
      else
        raise CbetaError.new(400), "不支援的 facet 欄位：#{facet_by}"
      end
    end

    # boost 已把 _score 正規化成出現次數，四捨五入去掉浮點誤差。
    def term_hits_from_score(score)
      score.to_f.round
    end

    # 組成與舊 Manticore 回傳一致的單筆結果 (symbol key)。
    # key 的順序刻意與舊 SearchController#init_fields 相同，讓 JSON 輸出一致。
    def row_from_hit(hit, query)
      source = hit['_source'] || {}
      row = { id: hit['_id'].to_i }
      # NEAR / Exclude 的 _score 不是出現次數，term_hits 由呼叫端另外計算
      row[:term_hits] = term_hits_from_score(hit['_score']) if query.es_countable?
      row.merge!(
        canon: source['canon'],
        category: source['category'],
        file: source['file'],
        work: source['work'],
        juan: source['juan'],
        title: source['title'],
        byline: source['byline'],
        creators: source['creators'],
        creators_with_id: source['creators_with_id'],
        time_dynasty: source['dynasty'],
        time_from: source['time_from'],
        time_to: source['time_to'],
        juan_list: source['juan_list']
      )
      # 以下欄位舊版不回傳，供呼叫端內部使用 (輸出前會被 fields 過濾掉)
      row[:vol] = source['vol']
      row[:work_type] = source['work_type']
      row
    end
  end
end
