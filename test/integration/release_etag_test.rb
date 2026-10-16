require 'test_helper'

# 內容只隨資料版本改變的端點: 以 ETag 支援條件式請求 (304)
class ReleaseEtagTest < ActionDispatch::IntegrationTest
  test '第二次帶 If-None-Match 時回 304' do
    get '/api/collections'
    assert_response :success
    etag = response.headers['ETag']
    assert etag.present?

    get '/api/collections', headers: { 'If-None-Match' => etag }
    assert_response :not_modified
    assert_empty response.body
  end

  # 304 只用於 GET / HEAD; 這些端點也接受 POST
  test 'POST 帶 If-None-Match 時仍回傳完整內容' do
    get '/api/collections'
    etag = response.headers['ETag']

    post '/api/collections', headers: { 'If-None-Match' => etag }
    assert_response :success
    assert_not_empty response.body
  end

  test '回應含每次不同的 time 欄位時, ETag 仍然固定' do
    get '/works/toc', params: { work: 'T0001' }
    first = response.headers['ETag']
    get '/works/toc', params: { work: 'T0001' }

    assert_equal first, response.headers['ETag']
  end

  test '不同參數 (含 JSONP callback) 的 ETag 不同' do
    get '/works/toc', params: { work: 'T0001' }
    a = response.headers['ETag']
    get '/works/toc', params: { work: 'T0001', callback: 'cb' }

    refute_equal a, response.headers['ETag']
  end

  test '資料版本或程式版號改變時 ETag 也改變' do
    get '/api/collections'
    etag = response.headers['ETag']

    with_config(Rails.configuration.cb, :r, 'ZZZZ') do
      get '/api/collections', headers: { 'If-None-Match' => etag }
    end
    assert_response :success
  end

  test '資料檔更新但季號不變時 ETag 也改變' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'toc.json')
      File.write(path, '{}')
      WorksController.define_method(:toc_path) { |_w| path }

      get '/works/toc', params: { work: 'T0001' }
      etag = response.headers['ETag']
      File.utime(Time.now + 10, Time.now + 10, path)
      get '/works/toc', params: { work: 'T0001' }, headers: { 'If-None-Match' => etag }

      assert_response :success
    ensure
      WorksController.remove_method(:toc_path)
    end
  end

  # 錯誤回應不可帶 release ETag, 否則錯誤恢復後瀏覽器仍會拿到 304 而一直看到錯誤。
  # (Rack::ETag 會依錯誤內容另算 ETag, 內容一變就對不上, 是安全的)
  test '以 HTTP 200 回傳的錯誤, 恢復後驗證會拿到正常內容' do
    begin
      Canon.define_singleton_method(:order) { |*| raise CbetaError.new(500), 'db down' }
      get '/textref/data'
      assert_response :success
      assert_match(/db down/, response.body)
      error_etag = response.headers['ETag']
    ensure
      Canon.singleton_class.remove_method(:order)
    end

    get '/textref/data', headers: { 'If-None-Match' => error_etag }
    assert_response :success
    refute_match(/db down/, response.body)
  end

  test '例外造成的錯誤回應不帶 release ETag' do
    get '/api/collections'
    release_etag = response.headers['ETag']

    Canon.define_singleton_method(:all) { raise CbetaError.new(503), 'db down' }
    get '/api/collections'

    assert_response :service_unavailable
    refute_equal release_etag, response.headers['ETag']
  ensure
    Canon.singleton_class.remove_method(:all)
  end

  private

  def with_config(config, key, value)
    original = config[key]
    config[key] = value
    yield
  ensure
    config[key] = original
  end
end
