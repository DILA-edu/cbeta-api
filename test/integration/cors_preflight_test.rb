# frozen_string_literal: true

require 'test_helper'

# CORS 預檢（設計文件 8）。
#
# CORS 的回應 header 由 Apache 提供,Rails 只負責讓 OPTIONS 得到 2xx ——
# 預檢必須是 2xx 才通過。
class CorsPreflightTest < ActionDispatch::IntegrationTest
  test 'OPTIONS 到 API endpoint 回 204' do
    process :options, '/search', headers: {
      'Origin' => 'https://allowed.example.com',
      'Access-Control-Request-Method' => 'GET',
      'Access-Control-Request-Headers' => 'Authorization'
    }
    assert_response :no_content
  end

  test 'OPTIONS 到巢狀路徑回 204' do
    process :options, '/api/collections'
    assert_response :no_content

    process :options, '/v1/tools/search'
    assert_response :no_content
  end

  test 'OPTIONS 到根路徑回 204' do
    process :options, '/'
    assert_response :no_content
  end

  test 'OPTIONS 到不存在的路徑也回 204（預檢不該洩漏 route 是否存在）' do
    process :options, '/no/such/thing'
    assert_response :no_content
  end

  test 'OPTIONS 不需要 API key' do
    original = Rails.configuration.api_key_required
    Rails.configuration.api_key_required = true

    process :options, '/search', headers: { 'Origin' => 'https://evil.example.com' }
    assert_response :no_content
  ensure
    Rails.configuration.api_key_required = original
  end

  test 'OPTIONS route 不影響 GET / POST' do
    get '/health'
    assert_response :success

    get '/changes'
    assert_response :success
  end

  test '含副檔名的路徑也吃得到（format: false）' do
    process :options, '/report/daily.csv'
    assert_response :no_content
  end
end
