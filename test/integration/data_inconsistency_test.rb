require 'test_helper'

# 資料不一致或參數不齊時不應變成 500, 也不應回傳重複資料。
class DataInconsistencyTest < ActionDispatch::IntegrationTest
  CN = { 'Referer' => 'https://example.cn/' }.freeze

  test 'works 依冊號查詢時, 跨冊佛典不會重複出現' do
    # 字串範圍比較下 "T05..T07" 落在 "T05".."T06" 之間, 原本會被加兩次
    Work.create!(n: 'T0220', canon: 'T', vol: 'T05..T07', title: '大般若波羅蜜多經')

    get '/works', params: { canon: 'T', vol_start: '5', vol_end: '6' }

    assert_equal(%w[T0220], response.parsed_body['results'].map { it['work'] })
  end

  test 'works 依冊號查詢時, 完全涵蓋查詢範圍的跨冊佛典仍會列出' do
    Work.create!(n: 'T0220', canon: 'T', vol: 'T05..T07', title: '大般若波羅蜜多經')

    get '/works', params: { canon: 'T', vol_start: '6' }

    assert_equal(%w[T0220], response.parsed_body['results'].map { it['work'] })
  end

  test 'works 沒帶已知參數且來自 .cn 時回空結果, 不出錯' do
    get '/works', headers: CN

    assert_response :success
    body = response.parsed_body
    refute body.key?('error'), body.inspect
    assert_equal 0, body['num_found']
  end

  test 'Asia Network API: juan_lines 有資料但 works 缺該部佛典時回 404' do
    JuanLine.create!(work: 'T9999', vol: 'T99', juan: 1, lb: '0001a01',
                     uuid: 'orphan-uuid', content_uuid: 'orphan-content')

    %w[/api/sections/orphan-uuid /api/sections/orphan-uuid/content_units].each do |path|
      get path
      assert_response :not_found, path
    end
  end
end
