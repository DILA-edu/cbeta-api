require 'test_helper'

# 查無資料或參數不齊時，不應該回 500；錯誤回應也不帶 backtrace（會洩漏伺服器路徑）。
class NotFoundResponsesTest < ActionDispatch::IntegrationTest
  setup do
    # 原書目錄: 各藏第一層是 orig-T 等，冊的 label 以冊號開頭 (見 import:catalog)
    CatalogEntry.create!(n: 'orig-T.001', parent: 'orig-T', label: 'T01 阿含部上 T0001-0098', sort: 1)
    CatalogEntry.create!(n: 'orig-T.001.001', parent: 'orig-T.001', label: '長阿含經', sort: 1)
  end

  test 'works?creator_name 只找尚未確認 ID 的作譯者' do
    Work.create!(n: 'T9998', canon: 'T', title: '甲', creators: '無名氏', creators_with_id: '')
    Work.create!(n: 'T9999', canon: 'T', title: '乙', creators: '無名氏', creators_with_id: '無名氏(A999999)')

    get '/works', params: { creator_name: '無名' }

    assert_response :success
    assert_equal(%w[T9998], response.parsed_body['results'].map { it['work'] })
  end

  test 'catalog_entry?vol= 以冊號取得原書目錄' do
    get '/catalog_entry', params: { vol: 'T01' }
    assert_equal(%w[orig-T.001.001], response.parsed_body['results'].map { it['n'] })

    get '/catalog_entry', params: { vol: 'T99' }
    assert_equal 0, response.parsed_body['num_found']
  end

  test 'toc?q=冊號 轉到 catalog_entry，查無資料時回空結果' do
    get '/toc', params: { q: 'T01' }
    assert_redirected_to '/catalog_entry?q=orig-T.001'

    %w[T99 T01n9999].each do |q|
      get '/toc', params: { q: }
      assert_response :success
      assert_equal 0, response.parsed_body['num_found'], q
    end
  end

  test '缺少 work 參數時 juans 與 works/toc 回空結果' do
    get '/juans'
    assert_equal 0, response.parsed_body['num_found']

    get '/works/toc'
    assert_equal 0, response.parsed_body['num_found']
  end

  test 'lines 的 linehead 不存在時回空結果' do
    get '/lines', params: { linehead: 'T01n0001_p9999a99', before: 1, after: 1 }

    assert_response :success
    assert_equal 0, response.parsed_body['num_found']
  end

  test 'juans/goto 缺少參數時回 400 錯誤碼' do
    get '/juans/goto'

    assert_response :success
    assert_equal 400, response.parsed_body.dig('error', 'code')
  end

  test 'Asia Network 的 uuid 不存在時回 404' do
    %w[
      /api/collections/nope/resources /api/resources/nope/sections
      /api/sections/nope /api/sections/nope/content_units /works?uuid=nope
    ].each do |path|
      get path

      assert_response :not_found, path
      assert_equal 404, response.parsed_body.dig('error', 'code'), path
    end
  end

  # 從未正常運作而移除的 route (/category 永遠 500、edition 沒有對應的 action)
  test '已移除的 route 回 404' do
    %w[/category/阿含部類 /work/T0001/juan/1/edition/CBETA].each do |path|
      assert_raises(ActionController::RoutingError, path) { Rails.application.routes.recognize_path(path) }
    end
  end

  test '錯誤回應不帶 backtrace' do
    get '/search', params: { q: '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1) }

    assert_match(/長度不得大於/, response.parsed_body['error'])
    refute_includes response.body, 'backtrace'
    refute_includes response.body, Rails.root.to_s
  end

  test '錯誤訊息裡的檔案路徑去掉伺服器的絕對路徑' do
    get '/search/kwic', params: { work: 'T0001', juan: 999, q: '法' }

    assert_match(%r{\A檔案不存在: data/kwic/}, response.parsed_body['error'])
    refute_includes response.body, Rails.root.to_s
  end
end
