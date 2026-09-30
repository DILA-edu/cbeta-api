require 'test_helper'
require 'json_schemer'

# doc/openapi.yaml 本身的檢查。實際回應是否符合 spec 要打有資料的 server，
# 見 test_remote/test_openapi_all_in_one.rb。
class OpenapiSpecTest < ActionDispatch::IntegrationTest
  SPEC_PATH = Rails.root.join('doc/openapi.yaml')

  setup do
    @document = YAML.safe_load_file(SPEC_PATH)
    @openapi = JSONSchemer.openapi(@document)
  end

  test 'spec 符合 OpenAPI 3.1 規範' do
    errors = @openapi.validate.map { it['error'] }
    assert_empty errors
  end

  # 不需要 Elasticsearch 就能產生的回應，可以在本機直接驗。
  test 'Elasticsearch 連不上時的 502 回應符合 Error schema' do
    conf = Rails.configuration.x.elasticsearch
    original = conf.url
    conf.url = 'http://127.0.0.1:9599'
    get '/search/all_in_one', params: { q: '法鼓', cache: '0' }

    assert_response :bad_gateway
    assert_conform 'Error', JSON.parse(response.body)
  ensure
    conf.url = original
  end

  test '過長的 q 回應符合 SearchError schema' do
    get '/search/all_in_one', params: { q: '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1) }

    assert_response :success
    assert_conform 'SearchError', JSON.parse(response.body)
  end

  test 'q 的 maxLength 與 MAX_QUERY_LENGTH 一致' do
    parameters = @document.dig('paths', '/search/all_in_one', 'get', 'parameters')
    q = parameters.find { it['name'] == 'q' }
    assert_equal ApplicationController::MAX_QUERY_LENGTH, q.dig('schema', 'maxLength')
  end

  test '/openapi.json 的版號取自 VERSION、servers 指向目前的站台' do
    get '/openapi.json'

    assert_response :success
    spec = response.parsed_body
    assert_equal Rails.configuration.x.ver, spec.dig('info', 'version')
    assert_equal [ { 'url' => 'http://www.example.com' } ], spec['servers']
    assert_empty(JSONSchemer.openapi(spec).validate.map { it['error'] })
  end

  test '/openapi.json 不納管 API key' do
    get '/openapi.json'

    assert_response :success
    assert_nil response.headers['X-CBETA-API-Key']
  end

  private

  def assert_conform(name, body)
    errors = @openapi.schema(name).validate(body).map { it['error'] }
    assert_empty errors, "回應不符合 #{name} schema"
  end
end
