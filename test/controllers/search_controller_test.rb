require 'test_helper'

class SearchControllerTest < ActionDispatch::IntegrationTest
  # SearchController 自己註冊了 rescue_from Exception, with: :error_handler,
  # 子類別的 handler 優先於 ApplicationController 的 rescue_from CbetaError,
  # 所以它遇到 CbetaError 仍是回 200 + body 裡的 error 欄位（既有 client 依賴這個行為）。
  test "search 過長的 q 仍由 SearchController 自己的 handler 處理" do
    long_q = '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1)
    get '/search', params: { q: long_q }
    assert_response :success
    body = JSON.parse(response.body)
    assert_match(/長度不得大於/, body['error'])
  end
end
