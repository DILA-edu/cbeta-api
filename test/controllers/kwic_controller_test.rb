require 'test_helper'

class KwicControllerTest < ActionDispatch::IntegrationTest
  # 過長的 q 應在連到 KWIC 後端之前就被擋下，回傳 JSON 錯誤而非 500。
  test "search/kwic 拒絕過長的 q" do
    long_q = '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1)
    get '/search/kwic', params: { q: long_q, work: 'T0001', juan: 1 }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_match(/長度不得大於/, body['error'])
  end
end
