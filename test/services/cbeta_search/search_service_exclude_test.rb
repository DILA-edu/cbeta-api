require 'test_helper'

# Exclude 的候選階段。
#
# 「"菩薩" -"諸菩薩"」這種查詢的候選有一萬五千多卷，而真正要顯示的只有當頁十幾筆。
# 候選階段因此只取必要欄位 (LIGHT_SOURCE_FIELDS)，完整欄位等分頁後才補 (rows_by_ids)。
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

  test 'all_candidates 預設取完整欄位, light 只取必要欄位' do
    svc, client = service([{ 'hits' => { 'hits' => [] } }])
    svc.all_candidates(phrase('菩薩'), params: {})
    assert_equal CbetaSearch::TextIndex.source_fields, client.bodies.first['_source'],
                 '預設 (NEAR 走這條) 維持完整欄位'

    svc, client = service([{ 'hits' => { 'hits' => [] } }])
    svc.all_candidates(phrase('菩薩'), params: {}, light: true)
    assert_equal CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS, client.bodies.first['_source']
    assert_operator client.bodies.first['_source'].size, :<,
                    CbetaSearch::TextIndex.source_fields.size
  end

  test 'light 取回的欄位足夠 all_in_one 的 my_facet 使用' do
    needed = %w[canon category work juan title creators_with_id dynasty]
    assert_equal needed.sort, CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS.sort
  end

  test 'exclude_candidates 走 light, 並逐卷相減 term_hits' do
    responses = [
      # simple_search: 排除字串「諸菩薩」的出現次數
      { 'hits' => { 'hits' => [hit(1, 3.0, { 'work' => 'T0001', 'juan' => 1 })] } },
      # all_candidates: 「菩薩」的候選
      { 'hits' => { 'hits' => [
        hit(1, 10.0, source(work: 'T0001', juan: 1)),
        hit(2, 5.0, source(work: 'T0002', juan: 1))
      ] } }
    ]
    svc, client = service(responses)

    rows = svc.exclude_candidates(exclude_query, params: {})

    assert_equal 2, rows.size
    assert_equal 7, rows[0][:term_hits], '10 - 3'
    assert_equal 5, rows[1][:term_hits], '沒有被排除的卷, 次數不變'
    assert_equal CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS, client.bodies.last['_source']
  end

  test 'exclude_candidates 相減後歸零的卷不算符合' do
    responses = [
      { 'hits' => { 'hits' => [hit(1, 10.0, { 'work' => 'T0001', 'juan' => 1 })] } },
      { 'hits' => { 'hits' => [hit(1, 10.0, source(work: 'T0001', juan: 1))] } }
    ]
    svc, = service(responses)

    assert_empty svc.exclude_candidates(exclude_query, params: {})
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

  test 'search_exclude 只對當頁補欄位' do
    responses = [
      { 'hits' => { 'hits' => [] } }, # simple_search: 沒有要排除的
      { 'hits' => { 'hits' => [
        hit(1, 10.0, source(work: 'T0001', juan: 1)),
        hit(2, 5.0, source(work: 'T0002', juan: 1)),
        hit(3, 2.0, source(work: 'T0003', juan: 1))
      ] } },
      { 'hits' => { 'hits' => [hit(2, 1.0, source(work: 'T0002', juan: 1, juan_list: '1'))] } }
    ]
    svc, client = service(responses)

    r = svc.send(:search_exclude, exclude_query, params: {}, start: 1, rows: 1,
                                                field: nil, default_sort: nil, t1: Time.now)

    assert_equal 3, r[:num_found], '總數是全部候選'
    assert_equal 17, r[:total_term_hits]
    assert_equal 1, r[:results].size
    assert_equal 'T0002', r[:results].first[:work]
    assert_equal %w[2], client.bodies.last.dig('query', 'ids', 'values'), '只補當頁那一筆'
  end
end
