require 'test_helper'

# Exclude 的候選階段。
#
# 「"菩薩" -"諸菩薩"」這種查詢的候選有一萬五千多卷，而真正要顯示的只有當頁十幾筆。
# 候選階段因此不取 _source (見 SearchService::SOURCE_MODES)，只用 _id 對應兩次
# 查詢的同一卷、用 _score 取出現次數，完整欄位等分頁後才補 (rows_by_ids)。
# 這裡鎖的是「省欄位不會省掉正確性」: 相減的算法、term_hits、順序都不能變。
class CbetaSearch::SearchServiceExcludeTest < ActiveSupport::TestCase
  # 記下每次送出的 body，並依序回覆預先準備好的 response。
  class FakeClient
    attr_reader :bodies

    def initialize(responses)
      @responses = responses
      @bodies = []
    end

    def search(index:, body:)
      @bodies << Marshal.load(Marshal.dump(body))
      @responses.shift || empty_response
    end

    private

    def empty_response = { 'hits' => { 'hits' => [] } }
  end

  def hit(id, score, source)
    { '_id' => id.to_s, '_score' => score, '_source' => source, 'sort' => [score, id] }
  end

  # _source: false 時 ES 回傳的 hit 長這樣 —— 沒有 _source 這個 key。
  def bare_hit(id, score)
    { '_id' => id.to_s, '_score' => score, 'sort' => [score, id] }
  end

  def source(work:, juan:, **extra)
    { 'work' => work, 'juan' => juan, 'canon' => 'T', 'category' => '般若部類',
      'title' => "#{work} 標題", 'creators_with_id' => '鳩摩羅什(A001583)',
      'dynasty' => '姚秦' }.merge(extra.transform_keys(&:to_s))
  end

  def service(responses)
    client = FakeClient.new(responses)
    [CbetaSearch::SearchService.new(client:), client]
  end

  def phrase(text)
    CbetaSearch::Query.new(type: :phrase, raw: text, phrase: text)
  end

  def exclude_query
    CbetaSearch::Query.new(type: :exclude, raw: '"菩薩" -"諸菩薩"', phrase: '菩薩',
                           exclude_prefix: '諸')
  end

  test 'all_candidates 的三種 _source 模式' do
    svc, client = service([{ 'hits' => { 'hits' => [] } }])
    svc.all_candidates(phrase('菩薩'), params: {})
    assert_equal CbetaSearch::TextIndex.source_fields, client.bodies.first['_source'],
                 '預設 (NEAR 走這條) 維持完整欄位'

    svc, client = service([{ 'hits' => { 'hits' => [] } }])
    svc.all_candidates(phrase('菩薩'), params: {}, source: :light)
    assert_equal CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS, client.bodies.first['_source']
    assert_operator client.bodies.first['_source'].size, :<,
                    CbetaSearch::TextIndex.source_fields.size

    svc, client = service([{ 'hits' => { 'hits' => [] } }])
    svc.all_candidates(phrase('菩薩'), params: {}, source: :none)
    assert_equal false, client.bodies.first['_source'], '完全不讀 _source'
  end

  test 'all_candidates 不認得的 _source 模式要報錯' do
    svc, = service([])
    assert_raises(CbetaError) { svc.all_candidates(phrase('菩薩'), params: {}, source: :tiny) }
  end

  test 'light 取回的欄位足夠 all_in_one 的 my_facet 使用' do
    needed = %w[canon category work juan title creators_with_id dynasty]
    assert_equal needed.sort, CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS.sort
  end

  test 'exclude_candidates 預設不取 _source, 並逐卷相減 term_hits' do
    responses = [
      # simple_search: 排除字串「諸菩薩」的出現次數 (沒有 _source)
      { 'hits' => { 'hits' => [bare_hit(1, 3.0)] } },
      # all_candidates: 「菩薩」的候選 (也沒有 _source)
      { 'hits' => { 'hits' => [bare_hit(1, 10.0), bare_hit(2, 5.0)] } }
    ]
    svc, client = service(responses)

    rows = svc.exclude_candidates(exclude_query, params: {})

    assert_equal 2, rows.size
    assert_equal [1, 2], rows.map { it[:id] }
    assert_equal 7, rows[0][:term_hits], '10 - 3'
    assert_equal 5, rows[1][:term_hits], '沒有被排除的卷, 次數不變'
    assert_equal [false, false], client.bodies.map { it['_source'] },
                 '兩次查詢都不讀 _source'
  end

  test 'exclude_candidates 的 _id 對應與 work/juan 無關' do
    # 兩次查詢打的是同一個 index，同一卷就是同一份 document。
    # 候選階段沒有 work / juan 可用，相減只能靠 _id —— 這裡用「_source 全空、
    # 只有 _id 不同」把這件事鎖住。
    responses = [
      { 'hits' => { 'hits' => [bare_hit(2, 4.0)] } },
      { 'hits' => { 'hits' => [bare_hit(1, 6.0), bare_hit(2, 6.0), bare_hit(3, 6.0)] } }
    ]
    svc, = service(responses)

    rows = svc.exclude_candidates(exclude_query, params: {})

    assert_equal [6, 2, 6], rows.map { it[:term_hits] }, '只有 _id=2 那一卷要被扣'
  end

  test 'exclude_candidates 相減後歸零的卷不算符合' do
    responses = [
      { 'hits' => { 'hits' => [bare_hit(1, 10.0)] } },
      { 'hits' => { 'hits' => [bare_hit(1, 10.0)] } }
    ]
    svc, = service(responses)

    assert_empty svc.exclude_candidates(exclude_query, params: {})
  end

  test 'exclude_candidates source: :light 時只有候選階段帶欄位' do
    responses = [
      { 'hits' => { 'hits' => [bare_hit(1, 3.0)] } },
      { 'hits' => { 'hits' => [hit(1, 10.0, source(work: 'T0001', juan: 1))] } }
    ]
    svc, client = service(responses)

    rows = svc.exclude_candidates(exclude_query, params: {}, source: :light)

    assert_equal 7, rows.first[:term_hits]
    assert_equal 'T0001', rows.first[:work], 'facet=1 要靠這些欄位'
    assert_equal false, client.bodies.first['_source'], '排除字串那一次仍然不必讀'
    assert_equal CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS, client.bodies.last['_source']
  end

  test 'rows_by_ids 補回完整欄位, 並保留候選階段算好的 term_hits' do
    page = [
      { id: 2, term_hits: 5, work: 'T0002', juan: 1 },
      { id: 1, term_hits: 7, work: 'T0001', juan: 1 }
    ]
    # ids query 的 _score 不是出現次數, 回傳順序也不保證與傳入相同
    responses = [{ 'hits' => { 'hits' => [
      hit(1, 1.0, source(work: 'T0001', juan: 1, juan_list: '1,2,3', byline: '鳩摩羅什譯')),
      hit(2, 1.0, source(work: 'T0002', juan: 1, juan_list: '1', byline: ''))
    ] } }]
    svc, client = service(responses)

    rows = svc.rows_by_ids(page, exclude_query)

    assert_equal %w[T0002 T0001], rows.map { it[:work] }, '要保持候選階段的順序'
    assert_equal [5, 7], rows.map { it[:term_hits] }, 'term_hits 不可被 _score 覆蓋'
    assert_equal '1', rows[0][:juan_list], 'light 階段省掉的欄位要補回來'
    assert_equal '鳩摩羅什譯', rows[1][:byline]
    assert_equal({ 'ids' => { 'values' => %w[2 1] } }, client.bodies.first['query'])
  end

  test 'rows_by_ids 對空的當頁不發請求' do
    svc, client = service([])

    assert_empty svc.rows_by_ids([], exclude_query)
    assert_empty client.bodies
  end

  test 'rows_by_ids 找不到的 id 保留原本那一列' do
    page = [{ id: 9, term_hits: 4, work: 'T0009', juan: 1 }]
    svc, = service([{ 'hits' => { 'hits' => [] } }])

    rows = svc.rows_by_ids(page, exclude_query)

    assert_equal page, rows
  end

  # ===== 相減下推到 Elasticsearch 的路徑 (#exclude_search) =====
  #
  # 三個請求，順序固定:
  #   1. composite aggregation 取排除字串的逐卷次數
  #   2. 主要詞組包 script_score，只取當頁
  #   3. hit_count 取主要詞組的總次數
  def composite_response(buckets, after_key: nil)
    agg = { 'buckets' => buckets.map do |work, juan, hits|
      { 'key' => { 'work' => work, 'juan' => juan }, 'hits' => { 'value' => hits.to_f } }
    end }
    agg['after_key'] = after_key if after_key
    { 'hits' => { 'hits' => [] }, 'aggregations' => { 'juans' => agg } }
  end

  def hit_count_response(total)
    { 'hits' => { 'hits' => [] },
      'aggregations' => { 'total_term_hits' => { 'value' => total.to_f } } }
  end

  def page_response(hits, total)
    { 'hits' => { 'total' => { 'value' => total }, 'hits' => hits } }
  end

  test 'exclude_search 三個請求: composite agg、當頁、hit_count' do
    responses = [
      composite_response([['T0001', 1, 3]]),
      page_response([hit(1, 10.0, source(work: 'T0001', juan: 1)),
                     hit(2, 5.0, source(work: 'T0002', juan: 1))], 2),
      hit_count_response(15)
    ]
    svc, client = service(responses)

    r = svc.exclude_search(exclude_query, params: {}, start: 0, rows: 20)

    assert_equal 3, client.bodies.size, '只發三個請求, 不逐筆取回候選'
    assert_equal 2, r[:num_found], 'num_found 取自當頁查詢的 hits.total'
    assert_equal 12, r[:total_term_hits], 'sum_a(15) - sum_b(3)'
    assert_equal [7, 5], r[:results].map { it[:term_hits] }, '當頁逐筆在 Ruby 端相減'
    assert_equal %w[T0001 T0002], r[:results].map { it[:work] }
  end

  test 'exclude_search 的當頁查詢: script_score + min_score + 分頁' do
    responses = [composite_response([['T0001', 1, 3]]), page_response([], 0),
                 hit_count_response(15)]
    svc, client = service(responses)
    svc.exclude_search(exclude_query, params: {}, start: 40, rows: 20)

    body = client.bodies[1]
    script = body.dig('query', 'script_score', 'script')
    assert_equal CbetaSearch::SearchService::EXCLUDE_SCRIPT, script['source']
    assert_equal({ 'T0001/1' => 3 }, script.dig('params', 'sub'),
                 'key 要與 script 裡的 work + "/" + juan 同格式')
    assert_equal CbetaSearch::SearchService::MIN_ADJUSTED_SCORE, body['min_score']
    assert_equal 40, body['from']
    assert_equal 20, body['size']
    assert_equal CbetaSearch::TextIndex.source_fields, body['_source'], '當頁要完整欄位'
    assert body['track_scores'], 'term_hits 靠 _score, 不能關掉'
  end

  # script 回傳的是「相減前」的次數 a，只把 a <= b 的卷歸零。
  # 這樣 order=term_hits 的排序鍵與舊版 (Manticore 以及遷移後的逐卷相減版)
  # 相同 —— 兩者都是依 a 排序、之後才相減。
  test 'EXCLUDE_SCRIPT 回傳相減前的分數, 只把被排除光的卷歸零' do
    script = CbetaSearch::SearchService::EXCLUDE_SCRIPT
    assert_includes script, 'Math.round(_score)'
    assert_includes script, "doc['work'].value + '/' + doc['juan'].value"
    assert_includes script, 'return a > b ? a : 0;'
  end

  test 'exclude_subtract_map 以 after_key 翻頁, 不會被 size 截斷' do
    batch = CbetaSearch::SearchService::COMPOSITE_BATCH_SIZE
    full = Array.new(batch) { |i| ["T#{format('%04d', i)}", 1, 1] }
    responses = [
      composite_response(full, after_key: { 'work' => 'T9998', 'juan' => 1 }),
      composite_response([['T9999', 2, 4]])
    ]
    svc, client = service(responses)

    subtract = svc.exclude_subtract_map(phrase('諸菩薩'), params: {})

    assert_equal batch + 1, subtract.size, '兩頁都要收進來'
    assert_equal 4, subtract['T9999/2']
    assert_equal({ 'work' => 'T9998', 'juan' => 1 },
                 client.bodies.last.dig('aggs', 'juans', 'composite', 'after'))
    assert_equal false, client.bodies.first['_source'], 'aggregation 不必回傳 hit'
    assert_equal 0, client.bodies.first['size']
  end

  test 'search_exclude 保持與 #search 相同的 key 順序' do
    responses = [composite_response([]), page_response([], 0), hit_count_response(0)]
    svc, = service(responses)

    r = svc.send(:search_exclude, exclude_query, params: {}, start: 0, rows: 20,
                                                field: nil, default_sort: nil, t1: Time.now)

    assert_equal %i[query_string time num_found total_term_hits cache_key results], r.keys
  end

  test 'search_exclude 超出 max_result_window 要報錯' do
    svc, = service([])
    window = CbetaSearch::IndexBase::MAX_RESULT_WINDOW

    assert_raises(CbetaError) do
      svc.send(:search_exclude, exclude_query, params: {}, start: window, rows: 20,
                                               field: nil, default_sort: nil, t1: Time.now)
    end
  end
end
