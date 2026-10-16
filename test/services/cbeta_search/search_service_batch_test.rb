require 'test_helper'

# 原本逐一發送的請求改成一次送出: facet 的五個維度、variants 的逐詞計數。
# 鎖住「合併後每一份的查詢內容與分開查詢相同」以及回應的拆解。
class CbetaSearch::SearchServiceBatchTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :search_bodies, :msearch_bodies

    def initialize(search: [], msearch: [])
      @search = search
      @msearch = msearch
      @search_bodies = []
      @msearch_bodies = []
    end

    # index: 是 Elasticsearch client 的介面, 這個 mock 用不到但簽名必須保留
    def search(index:, body:) # rubocop:disable Lint/UnusedMethodArgument
      @search_bodies << Marshal.load(Marshal.dump(body))
      @search.shift
    end

    def msearch(index:, body:) # rubocop:disable Lint/UnusedMethodArgument
      @msearch_bodies << Marshal.load(Marshal.dump(body))
      @msearch.shift
    end
  end

  def phrase(text) = CbetaSearch::Query.new(type: :phrase, raw: text, phrase: text)

  def buckets(*rows)
    { 'buckets' => rows.map { |key, docs, hits| { 'key' => key, 'doc_count' => docs, 'hits' => { 'value' => hits } } } }
  end

  test 'facets 一次 request 取回多個維度, 各自依 hits 遞減' do
    client = FakeClient.new(search: [ { 'aggregations' => {
      'facet_canon' => buckets([ 'T', 5, 7.0 ], [ 'X', 6, 9.0 ]),
      'facet_work' => buckets([ 'T0001', 2, 3.0 ])
    } } ])
    svc = CbetaSearch::SearchService.new(client:)

    r = svc.facets(phrase('法鼓'), params: {}, facet_bys: %w[canon work])

    assert_equal 1, client.search_bodies.size
    assert_equal %w[canon work], r.keys
    assert_equal [ { canon: 'X', docs: 6, hits: 9 }, { canon: 'T', docs: 5, hits: 7 } ], r['canon']
    assert_equal [ { work: 'T0001', docs: 2, hits: 3 } ], r['work']

    aggs = client.search_bodies.first['aggs']
    assert_equal 'canon', aggs.dig('facet_canon', 'terms', 'field')
    assert_equal 'work', aggs.dig('facet_work', 'terms', 'field')
    assert_equal 0, client.search_bodies.first['size']
  end

  test 'facet (單一維度) 與 facets 的查詢內容相同' do
    single = FakeClient.new(search: [ { 'aggregations' => { 'facet_dynasty' => buckets([ '唐', 1, 1.0 ]) } } ])
    multi = FakeClient.new(search: [ { 'aggregations' => { 'facet_dynasty' => buckets([ '唐', 1, 1.0 ]) } } ])

    a = CbetaSearch::SearchService.new(client: single).facet(phrase('法鼓'), params: {}, facet_by: 'dynasty')
    b = CbetaSearch::SearchService.new(client: multi).facets(phrase('法鼓'), params: {}, facet_bys: %w[dynasty])

    assert_equal a, b['dynasty']
    assert_equal single.search_bodies, multi.search_bodies
  end

  test 'facets 不支援的維度回 400' do
    svc = CbetaSearch::SearchService.new(client: FakeClient.new)
    error = assert_raises(CbetaError) { svc.facets(phrase('法鼓'), params: {}, facet_bys: %w[canon foo]) }
    assert_equal 400, error.code
  end

  test 'hit_count_all 一次 _msearch, 每筆的 body 與 hit_count 相同' do
    single = FakeClient.new(search: [ { 'aggregations' => { 'total_term_hits' => { 'value' => 5.0 } } } ])
    CbetaSearch::SearchService.new(client: single).hit_count(phrase('無上'), params: {})

    client = FakeClient.new(msearch: [ { 'responses' => [
      { 'aggregations' => { 'total_term_hits' => { 'value' => 5.0 } } },
      { 'aggregations' => { 'total_term_hits' => { 'value' => 0.0 } } }
    ] } ])
    r = CbetaSearch::SearchService.new(client:).hit_count_all(%w[無上 旡上], params: {})

    assert_equal({ '無上' => 5, '旡上' => 0 }, r)
    assert_equal 1, client.msearch_bodies.size
    body = client.msearch_bodies.first
    assert_equal [ {}, single.search_bodies.first ], body.first(2), '與逐一查詢的 body 相同'
  end

  test 'hit_count_all 依 batch_size 分批, 重複詞組只問一次' do
    resp = ->(*values) { { 'responses' => values.map { { 'aggregations' => { 'total_term_hits' => { 'value' => it } } } } } }
    client = FakeClient.new(msearch: [ resp.(1.0, 2.0), resp.(3.0) ])

    r = CbetaSearch::SearchService.new(client:).hit_count_all(%w[甲 乙 甲 丙], params: {}, batch_size: 2)

    assert_equal({ '甲' => 1, '乙' => 2, '丙' => 3 }, r)
    assert_equal [ 4, 2 ], client.msearch_bodies.map(&:size)
  end

  test 'hit_count_all 單筆失敗時不可默默當成 0' do
    client = FakeClient.new(msearch: [ { 'responses' => [ { 'error' => { 'type' => 'search_phase_execution_exception' } } ] } ])

    error = assert_raises(CbetaError) do
      CbetaSearch::SearchService.new(client:).hit_count_all(%w[無上], params: {})
    end
    assert_equal 502, error.code
  end
end
