require 'test_helper'

class TocNodeControllerTest < ActionDispatch::IntegrationTest
  # 過長的 q 應在查詢 DB 之前就被擋下，回傳 JSON 錯誤。
  test "search/toc 拒絕過長的 q" do
    long_q = '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1)
    get '/search/toc', params: { q: long_q }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body['num_found']
    assert_match(/長度不得大於/, body['error'])
  end

  # q 未帶或為空字串時, 原本會走進 catalog/work/toc 三張表的 LIKE '%%' 全表掃描,
  # 實測會跑滿 rack-timeout 的 300 秒並佔住一個 Passenger process。
  test "search/toc 拒絕空的 q" do
    [ '', '   ' ].each do |q|
      get '/search/toc', params: { q: q }
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 0, body['num_found']
      assert_match(/缺少 q 參數/, body['error'])
    end
  end

  # 未帶 q 參數時原本會是 NoMethodError (undefined method 'match' for nil) 造成 500。
  test "search/toc 未帶 q 參數不應 500" do
    get '/search/toc'
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body['num_found']
    assert_match(/缺少 q 參數/, body['error'])
  end

  # label_path 由 import:toc 算好存在欄位; 欄位為空 (尚未重新匯入) 時沿 parent 查
  test 'search/toc 的 label_path 優先用欄位, 欄位為空時沿 parent 組出' do
    get '/search/toc', params: { q: '大本經' }
    child = response.parsed_body['results'].find { it['type'] == 'toc' }
    assert_equal '長阿含經/第一分初大本經第一', child['label_path'], '欄位為空時沿 parent 組出'

    # n 重複時以 n 反查會接錯祖先; 欄位是依實際的樹算出的, 不受影響
    TocNode.find_by!(n: 'T0001.1').update!(label_path: '另一組目次/第一分初大本經第一')
    get '/search/toc', params: { q: '大本經' }
    child = response.parsed_body['results'].find { it['type'] == 'toc' }
    assert_equal '另一組目次/第一分初大本經第一', child['label_path']
  end

  # 分頁: 每類各有 2 筆以上, 才測得到跨類別的邊界
  def setup_paging_data
    CatalogEntry.create!(n: 'orig-T.001', parent: 'orig-T', label: 'T01 阿含部上', sort: 1)
    CatalogEntry.create!(n: 'orig-T.002', parent: 'orig-T', label: 'T02 阿含部下', sort: 2)
    TocNode.create!(canon: 'T', work: 'T0001', file: 'T01n0001', n: 'T0001.2',
                    label: '阿含第二', juan: 1, lb: '0001a03', parent: 'T0001', sort_order: 'T0001.2')
    TocNode.create!(canon: 'T', work: 'T0001', file: 'T01n0001', n: 'T0001.3',
                    label: '阿含第三', juan: 1, lb: '0001a04', parent: 'T0001', sort_order: 'T0001.3')
  end

  def search_toc(params)
    get '/search/toc', params: { q: '阿含' }.merge(params)
    assert_response :success
    response.parsed_body
  end

  def row_keys(rows)
    rows.map { [ it['type'], it['n'] || it['work'], it['label'] || it['title'] ] }
  end

  test 'search/toc 未帶 rows 時全部回傳, 並附各類筆數' do
    setup_paging_data
    body = search_toc({})
    counts = body['counts']
    assert_equal %w[catalog toc work], counts.keys.sort
    assert_operator counts['catalog'], :>=, 2
    assert_operator counts['toc'], :>=, 2
    assert_equal counts.values.sum, body['num_found']
    assert_equal body['num_found'], body['results'].size
    # 順序: 部類目錄 → 經名 → 目次
    types = body['results'].map { it['type'] }
    assert_equal types.sort_by { TocNodeController::TYPES.index(it) }, types
  end

  test 'search/toc 以 start / rows 分頁, 各頁接起來與一次取回相同' do
    setup_paging_data
    all = search_toc({})
    total = all['num_found']

    pages = []
    (0...total).step(2) do |start|
      body = search_toc(start:, rows: 2)
      assert_equal total, body['num_found']
      assert_equal all['counts'], body['counts']
      pages.concat(body['results'])
    end
    assert_equal row_keys(all['results']), row_keys(pages)

    assert_empty search_toc(start: total, rows: 2)['results']
  end

  test 'search/toc 以 type 只取某幾類' do
    setup_paging_data
    all = search_toc({})

    body = search_toc(type: 'toc')
    assert_equal all['counts'], body['counts'], 'counts 不受 type 影響'
    assert_equal all['counts']['toc'], body['num_found']
    assert_equal [ 'toc' ], body['results'].map { it['type'] }.uniq

    body = search_toc(type: 'toc,catalog', start: 1, rows: 2)
    expected = all['results'].select { %w[catalog toc].include?(it['type']) }[1, 2]
    assert_equal row_keys(expected), row_keys(body['results'])
  end

  # 佛典不在 works 表的目次不會回傳, 也不能算進筆數, 否則分頁會缺筆
  test 'search/toc 的筆數不含佛典不存在的目次' do
    setup_paging_data
    before = search_toc({})
    TocNode.create!(canon: 'X', work: 'X9999', file: 'X99n9999', n: 'X9999.1',
                    label: '阿含不存在', juan: 1, lb: '0001a01', parent: 'X9999', sort_order: 'X9999.1')
    body = search_toc({})
    assert_equal before['counts'], body['counts']
    assert_equal body['num_found'], body['results'].size
  end

  test 'search/toc 的 rows=0 只回傳筆數' do
    setup_paging_data
    body = search_toc(rows: 0)
    assert_empty body['results']
    assert_operator body['num_found'], :>, 0
  end

  test 'search/toc 依佛典編號查詢也套用分頁與 type' do
    get '/search/toc', params: { q: 'T0001' }
    body = response.parsed_body
    assert_equal({ 'catalog' => 0, 'work' => 1, 'toc' => 0 }, body['counts'])
    assert_equal 1, body['num_found']

    get '/search/toc', params: { q: 'T0001', type: 'toc' }
    body = response.parsed_body
    assert_equal 0, body['num_found']
    assert_empty body['results']
  end

  test 'search/toc 拒絕格式錯誤的分頁參數' do
    [ { start: -1 }, { rows: 'abc' }, { rows: '1.5' }, { type: 'foo' }, { type: 'toc,juan' } ].each do |params|
      body = search_toc(params)
      assert_equal 0, body['num_found'], params.inspect
      assert body['error'].present?, params.inspect
    end
  end
end
