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

  # q 由使用者輸入，其中的 regex 特殊字元必須當成一般字元比對
  test "kwic_boolean_exclude 將 q 中的 regex 特殊字元視為一般字元" do
    se = Object.new
    def se.search_juan(q, opts) = [q, opts]

    c = SearchController.new
    c.instance_variable_set(:@q, '"般+若"')
    c.instance_variable_set(:@exclude, '般+若經')
    assert_equal ['般+若', { negative_lookahead: '經' }], c.send(:kwic_boolean_exclude, se, {})

    c.instance_variable_set(:@exclude, '大般+若')
    assert_equal ['般+若', { negative_lookbehind: '大' }], c.send(:kwic_boolean_exclude, se, {})
  end

  test "notes_highlight 將 q 中的 regex 特殊字元視為一般字元" do
    { '般若' => '般若', '般若$' => '般，若$', '般若\\' => '般，若\\', '般若{}' => '般。若{}' }.each do |q, text|
      c = SearchController.new
      c.params = ActionController::Parameters.new(q: q)
      c.instance_variable_set(:@q, q)
      r = { results: [{ content_w_puncs: "#{text}經", content: '', note_place: 'foot' }] }
      c.send(:notes_highlight, r)
      assert_equal "<mark>#{text}</mark>經", r[:results][0][:highlight], "q: #{q}"
    end
  end
end
