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

  # 空的 q 會 raise CbetaError.new(400)。Kwic3Controller 沒有自己的 rescue_from,
  # 在 ApplicationController 加上 handler 之前, 這裡回的是 500。
  test "search/kwic 空的 q 應回 400 而非 500" do
    get '/search/kwic', params: { q: '', work: 'T0001', juan: 1 }
    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal 400, body['error']['code']
    assert_match(/缺少 q 參數/, body['error']['message'])
  end

  # JSONP 的 client 讀不到 HTTP status, 錯誤回應仍要包 callback。
  test "search/kwic 錯誤回應支援 JSONP callback" do
    get '/search/kwic', params: { q: '', work: 'T0001', juan: 1, callback: 'cb' }
    assert_response :bad_request
    assert_match %r{application/javascript}, response.media_type
    # Rails 的 JSONP 會加上 /**/ 前綴（防 JSON hijacking）
    assert_match(%r{\A/\*\*/cb\(}, response.body)
  end
end
