require 'test_helper'

class SearchControllerTest < ActionDispatch::IntegrationTest
  # Elasticsearch 出問題時不該回 500 加 backtrace（那會洩漏伺服器路徑），
  # 而是 502 加一句可讀的訊息，細節只留在 log。
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

  test '過長的 q 在連到後端之前就被擋下' do
    with_elasticsearch_config(url: 'http://127.0.0.1:9599') do
      get '/search', params: { q: '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1) }

      body = JSON.parse(response.body)
      assert_match(/長度不得大於/, body['error'])
    end
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
