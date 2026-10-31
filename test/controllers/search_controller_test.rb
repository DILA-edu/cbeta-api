require 'test_helper'

class SearchControllerTest < ActionDispatch::IntegrationTest
  # Elasticsearch 出問題時不該回 500 加 backtrace（那會洩漏伺服器路徑），
  # 而是 502 加一句可讀的訊息，細節只留在 log。
  # k 的成本與它成正比 (Ruby 單執行緒 Smith-Waterman), 參數驗證在查 ES 之前
  test 'similar 的 k 超過上限時回錯誤訊息' do
    get '/search/similar', params: { q: '是日已過命亦隨減', k: (SearchController::SIMILAR_K_MAX + 1).to_s }

    assert_match(/k 參數 不得大於 #{SearchController::SIMILAR_K_MAX}/, response.parsed_body['error'])
  end

  test 'Elasticsearch 連不上時回 502，不回傳 backtrace' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search', params: { q: '法鼓' }

      assert_response :bad_gateway
      body = JSON.parse(response.body)
      assert_equal 502, body.dig('error', 'code')
      assert_match(/暫時無法使用/, body.dig('error', 'message'))
      refute_includes response.body, 'backtrace'
    end
  end

  test 'index 不存在時回 502 並指出是哪個 alias' do
    skip 'Elasticsearch 未啟動' unless elasticsearch_available?

    aliases = Rails.configuration.x.elasticsearch.aliases.merge(text: 'no_such_index_for_test')
    with_elasticsearch_config(aliases:) do
      get '/search', params: { q: '法鼓' }

      assert_response :bad_gateway
      body = JSON.parse(response.body)
      assert_equal 502, body.dig('error', 'code')
      assert_match(/no_such_index_for_test/, body.dig('error', 'message'))
      refute_includes response.body, 'backtrace'
    end
  end

  # all_in_one 有自己的 inline rescue，要確認它沒把 Elasticsearch 的錯誤
  # 攔成 500 加 backtrace。
  test 'all_in_one 的 Elasticsearch 錯誤同樣回 502，不回傳 backtrace' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search/all_in_one', params: { q: '法鼓', cache: '0' }

      assert_response :bad_gateway
      body = JSON.parse(response.body)
      assert_equal 502, body.dig('error', 'code')
      refute_includes response.body, 'backtrace'
    end
  end

  test '缺少 q 參數時不會碰到 Elasticsearch' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search'

      assert_response :success
      assert_equal '缺少必要參數：q', response.body
    end
  end

  # 這裡 raise 的是 CbetaError.new(400)。ApplicationController 有
  # rescue_from CbetaError（會回真正的 HTTP status），但 SearchController 自己註冊了
  # rescue_from Exception, with: :error_handler，子類別的 handler 優先，
  # 所以這裡仍是回 200 + body 裡的 error 欄位（既有 client 依賴這個行為）。
  test '過長的 q 在連到後端之前就被擋下' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search', params: { q: '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1) }

      assert_response :success
      body = JSON.parse(response.body)
      assert_match(/長度不得大於/, body['error'])
    end
  end

  # 以下錯誤都在連到 Elasticsearch 之前就擋下，回 200 + error (既有 client 依賴這個行為)。
  # /search 走 error_handler (error 為字串)；all_in_one 有自己的 rescue (error 為物件)。
  test '不支援的排序欄位回傳錯誤，不再靜默忽略' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search', params: { q: '法鼓', order: 'year' }
      assert_match(/order 參數不支援的欄位：year/, response.parsed_body['error'])

      get '/search/all_in_one', params: { q: '法鼓', order: 'year', cache: '0' }
      assert_equal 400, response.parsed_body.dig('error', 'code')
      assert_match(/order 參數不支援的欄位：year/, response.parsed_body.dig('error', 'message'))
    end
  end

  test '括號分組回傳錯誤，不再被當成標點去掉' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search/notes', params: { q: '("法鼓" | "印順") "迦葉"' }
      assert_match(/不支援括號分組/, response.parsed_body['error'])

      get '/search/all_in_one', params: { q: '("法鼓" | "印順") "迦葉"', cache: '0' }
      assert_equal 400, response.parsed_body.dig('error', 'code')
    end
  end

  # q 由使用者輸入，其中的 regex 特殊字元必須當成一般字元比對
  test 'notes_highlight 將 q 中的 regex 特殊字元視為一般字元' do
    { '般若' => '般若', '般若$' => '般，若$', '般若\\' => '般，若\\', '般若{}' => '般。若{}' }.each do |q, text|
      c = SearchController.new
      c.params = ActionController::Parameters.new(q: q)
      c.instance_variable_set(:@q, q)
      r = { results: [ { content_w_puncs: "#{text}經", content: '', note_place: 'foot' } ] }
      c.send(:notes_highlight, r)

      assert_equal "<mark>#{text}</mark>經", r[:results][0][:highlight], "q: #{q}"
    end
  end

  # SearchController 的 rescue_from Exception 會蓋過 ApplicationController 的
  # timeout handler, 原本逾時回 HTTP 200; 408 又會讓部分 client 自動重送
  # 負數原本送進 Elasticsearch (回 502), 兩段式分頁則取到最後幾筆
  test 'start / rows 為負數時回錯誤訊息' do
    %i[start rows].each do |key|
      get '/search/all_in_one', params: { q: '法鼓', key => -3 }

      assert_match(/#{key} 參數 不得小於 0/, response.parsed_body['error'])
    end
  end

  # notes / titles / chunks index 沒有 work_type 欄位, 原本帶了就靜默回 0 筆
  test 'notes、title、similar 帶 work_type 時回錯誤訊息' do
    %w[notes title similar].each do |action|
      get "/search/#{action}", params: { q: '法鼓', work_type: '一般' }

      assert_match(/不支援 work_type/, response.parsed_body['error'], action)
    end
  end

  test 'rack-timeout 逾時回 504' do
    SearchController.alias_method :__orig_all_in_one, :all_in_one
    SearchController.define_method(:all_in_one) do
      raise Rack::Timeout::RequestTimeoutException, request.env
    end

    get '/search/all_in_one', params: { q: '法鼓' }

    assert_response :gateway_timeout
    assert_equal 504, response.parsed_body.dig('error', 'code')
  ensure
    SearchController.alias_method :all_in_one, :__orig_all_in_one
    SearchController.remove_method :__orig_all_in_one
  end

  private

  # 暫時改寫 Elasticsearch 設定；SearchService 每個 request 都會重新讀，
  # 因此不必重啟 app。
  # 查詢走的是 config.x.elasticsearch.aliases（每個 index 一組），
  # 不是單一的 index_alias，見 CbetaSearch::IndexBase.index_alias。
  def with_elasticsearch_config(**overrides)
    conf = Rails.configuration.x.elasticsearch
    original = overrides.keys.to_h { |key| [key, conf.send(key)] }
    overrides.each { |key, value| conf.send("#{key}=", value) }
    yield
  ensure
    original.each { |key, value| conf.send("#{key}=", value) }
  end

  def elasticsearch_available?
    CbetaSearch::ElasticClient.build.ping
  rescue StandardError
    false
  end
end
