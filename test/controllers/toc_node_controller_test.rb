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
end
