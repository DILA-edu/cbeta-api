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
end
