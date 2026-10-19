require 'test_helper'

# search/notes 的 cursor 分段 (SearchService#cursor_search) 與 rows 上限。
#
# 2026-10 CBETA Online 試用時發現：notes 單字查詢可達 33 萬筆，而 start + rows
# 受 max_result_window (10 萬) 限制，匯出拿不到全部。這裡鎖的是 cursor 的契約：
# 第一段 cursor=*、之後傳 next_cursor、最後一段 next_cursor 為 nil。
class CbetaSearch::SearchServiceCursorTest < ActiveSupport::TestCase
  # 記下每次送出的 search (index 與 body)，並依序回覆預先準備好的 response。
  class FakeClient
    attr_reader :searches, :opened, :closed

    def initialize(responses)
      @responses = responses
      @searches = []
      @opened = []
      @closed = []
    end

    def search(index:, body:)
      @searches << { index:, body: Marshal.load(Marshal.dump(body)) }
      @responses.shift || { 'hits' => { 'hits' => [] } }
    end

    def open_point_in_time(index:, keep_alive:)
      @opened << { index:, keep_alive: }
      { 'id' => 'pit-1' }
    end

    def close_point_in_time(body:)
      @closed << body[:id]
    end
  end

  def note_hit(id, score: 1, sort: nil)
    { '_id' => id.to_s, '_score' => score, 'sort' => sort || [ 'T', 'T01', id, id ],
      '_source' => { 'work' => 'T0001', 'juan' => 1, 'canon' => 'T', 'lb' => "000#{id}" } }
  end

  def page(hits, total: nil, pit: 'pit-1')
    r = { 'hits' => { 'hits' => hits }, 'pit_id' => pit }
    r['hits']['total'] = { 'value' => total } if total
    r
  end

  def service(responses)
    client = FakeClient.new(responses)
    [ CbetaSearch::SearchService.new(index: CbetaSearch::NotesIndex, client:), client ]
  end

  def phrase(text)
    CbetaSearch::Query.new(type: :phrase, raw: text, phrase: text)
  end

  def exclude_query
    CbetaSearch::Query.new(type: :exclude, raw: '"菩薩" -"諸菩薩"', phrase: '菩薩',
                           exclude_prefix: '諸')
  end

  def cursor_state(cursor) = JSON.parse(Base64.urlsafe_decode64(cursor))

  test 'rows 超過上限時截斷而不是報錯, 只有 start 本身超出才報錯' do
    svc, = service([])
    max = CbetaSearch::IndexBase::MAX_RESULT_WINDOW

    assert_equal 20, svc.send(:window_rows, 0, 20)
    assert_equal max, svc.send(:window_rows, 0, 9_999_999)
    assert_equal 1, svc.send(:window_rows, max - 1, 9_999_999)
    assert_raises(CbetaError) { svc.send(:window_rows, max, 1) }
  end

  test 'search 送給 ES 的 size 是截過的 rows' do
    svc, client = service([ page([], total: 0), { 'aggregations' => {} } ])

    svc.search(phrase('佛'), params: {}, start: 99_990, rows: 9_999_999)

    assert_equal 99_990, client.searches.first[:body]['from']
    assert_equal 10, client.searches.first[:body]['size']
  end

  test '第一段開 PIT, 帶 PIT 的 search 不指定 index' do
    svc, client = service([ page([ note_hit(1), note_hit(2) ], total: 5), { 'aggregations' => {} } ])

    r = svc.cursor_search(phrase('佛'), params: {}, cursor: '*', rows: 2)

    assert_equal 1, client.opened.size
    assert_equal 'cbeta_notes_current', client.opened.first[:index]
    first = client.searches.first
    assert_nil first[:index]
    assert_equal({ 'id' => 'pit-1', 'keep_alive' => '5m' }, first[:body]['pit'])
    assert_nil first[:body]['search_after'], '第一段沒有 search_after'
    assert_equal 2, first[:body]['size']
    assert_equal 5, r[:num_found]
    assert_equal([ 1, 2 ], r[:results].map { it[:id] })
    assert_equal %i[query_string time num_found total_term_hits cache_key next_cursor results], r.keys
  end

  test 'next_cursor 帶著最後一筆的 sort, 下一段以它為 search_after' do
    svc, client = service([ page([ note_hit(1), note_hit(2, sort: [ 'T', 'T01', 'x', 9 ]) ], total: 3),
                           { 'aggregations' => {} } ])
    r = svc.cursor_search(phrase('佛'), params: {}, cursor: '*', rows: 2)
    assert_equal [ 'T', 'T01', 'x', 9 ], cursor_state(r[:next_cursor])['a']

    svc2, client2 = service([ page([ note_hit(3) ], total: 3), { 'aggregations' => {} } ])
    r2 = svc2.cursor_search(phrase('佛'), params: {}, cursor: r[:next_cursor], rows: 2)

    assert_empty client2.opened, '之後的段不再開 PIT'
    assert_equal [ 'T', 'T01', 'x', 9 ], client2.searches.first[:body]['search_after']
    assert_nil r2[:next_cursor], '不足 rows 筆就是最後一段'
    assert_equal [ 'pit-1' ], client2.closed, '最後一段釋放 PIT'
    assert_empty client.closed
  end

  test 'ES 換了 pit_id 時, next_cursor 用新的' do
    svc, = service([ page([ note_hit(1) ], total: 2, pit: 'pit-2'), { 'aggregations' => {} } ])

    r = svc.cursor_search(phrase('佛'), params: {}, cursor: '*', rows: 1)

    assert_equal 'pit-2', cursor_state(r[:next_cursor])['p']
  end

  test '換了查詢條件卻沿用舊 cursor 要報錯' do
    svc, = service([ page([ note_hit(1) ], total: 2), { 'aggregations' => {} } ])
    r = svc.cursor_search(phrase('佛'), params: {}, cursor: '*', rows: 1)

    svc2, = service([])
    e = assert_raises(CbetaError) do
      svc2.cursor_search(phrase('佛'), params: { canon: 'T' }, cursor: r[:next_cursor], rows: 1)
    end
    assert_equal 400, e.code
    assert_raises(CbetaError) { svc2.cursor_search(phrase('法'), params: {}, cursor: r[:next_cursor], rows: 1) }
  end

  test '無效的 cursor 要報錯' do
    svc, = service([])

    [ 'abc', Base64.urlsafe_encode64('[1]'), Base64.urlsafe_encode64('{"p":1}') ].each do |cursor|
      e = assert_raises(CbetaError) { svc.cursor_search(phrase('佛'), params: {}, cursor:, rows: 1) }
      assert_equal 'cursor 參數無效', e.message
    end
  end

  test 'rows 截到 CURSOR_MAX_ROWS, rows < 1 要報錯' do
    svc, client = service([ page([], total: 0), { 'aggregations' => {} } ])
    svc.cursor_search(phrase('佛'), params: {}, cursor: '*', rows: 9_999_999)
    assert_equal CbetaSearch::SearchService::CURSOR_MAX_ROWS, client.searches.first[:body]['size']

    assert_raises(CbetaError) { svc.cursor_search(phrase('佛'), params: {}, cursor: '*', rows: 0) }
  end

  test 'PIT 過期轉成 400, 其他 404 照常往外丟' do
    svc, client = service([])
    expired = Elastic::Transport::Transport::Errors::NotFound.new('[404] search_context_missing_exception')
    client.define_singleton_method(:search) { |**| raise expired }
    cursor = Base64.urlsafe_encode64(JSON.generate('p' => 'pit-1', 'a' => [ 1 ],
                                                   'd' => svc.send(:cursor_digest, phrase('佛'), {}, 'content')))

    e = assert_raises(CbetaError) { svc.cursor_search(phrase('佛'), params: {}, cursor:, rows: 1) }
    assert_match(/過期/, e.message)

    other = Elastic::Transport::Transport::Errors::NotFound.new('[404] index_not_found_exception')
    client.define_singleton_method(:search) { |**| raise other }
    assert_raises(Elastic::Transport::Transport::Errors::NotFound) do
      svc.cursor_search(phrase('佛'), params: {}, cursor:, rows: 1)
    end
  end

  test 'Exclude: 第一段全部掃過取得 num_found, 之後由 cursor 帶著走' do
    svc, client = service([
      # 第一段的 exclude_by_candidates: 排除字串 (id 2 有 1 次)、主要詞組全部候選
      page([ { '_id' => '2', '_score' => 1, 'sort' => [ 1 ] } ]),
      page([ { '_id' => '1', '_score' => 2, 'sort' => [ 1 ] }, { '_id' => '2', '_score' => 1, 'sort' => [ 2 ] } ]),
      # 當段: 主要詞組兩筆, 再對這兩筆查排除字串
      page([ note_hit(1, score: 2), note_hit(2, score: 1) ]),
      page([ { '_id' => '2', '_score' => 1 } ])
    ])

    r = svc.cursor_search(exclude_query, params: {}, cursor: '*', rows: 2)

    assert_equal 1, r[:num_found]
    assert_equal 2, r[:total_term_hits]
    assert_equal [ 1 ], r[:results].map { it[:id] }, 'id 2 被排除光'
    assert_equal 2, r[:results].first[:term_hits]
    assert r[:next_cursor], '原始筆數等於 rows, 還有下一段 (即使當段過濾後不足 rows)'
    assert_equal 1, cursor_state(r[:next_cursor])['n']

    minus = client.searches.last
    assert_equal 'cbeta_notes_current', minus[:index]
    assert_equal({ 'ids' => { 'values' => %w[1 2] } }, minus[:body].dig('query', 'bool', 'filter', 0))
  end

  test 'Exclude 的 facet 逐筆相減, 只回傳相減後仍 > 0 的' do
    svc, client = service([
      page([ { '_id' => '2', '_score' => 1, 'sort' => [ 1 ] } ]),
      page([ { '_id' => '1', '_score' => 3, '_source' => { 'canon' => 'T', 'category' => '阿含部類' } },
            { '_id' => '2', '_score' => 1, '_source' => { 'canon' => 'X' } } ])
    ])

    rows = svc.exclude_facet_rows(exclude_query, params: {})

    assert_equal 1, rows.size
    assert_equal 3, rows.first[:term_hits]
    assert_equal 'T', rows.first[:canon]
    assert_equal '', rows.first[:creators_with_id], 'nil 轉空字串, my_facet 才能 split'
    assert_equal CbetaSearch::SearchService::LIGHT_SOURCE_FIELDS, client.searches.last[:body]['_source']
  end
end
