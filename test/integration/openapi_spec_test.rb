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

  test '過長的 q 回應符合 LegacyError schema' do
    get '/search/all_in_one', params: { q: '佛' * (ApplicationController::MAX_QUERY_LENGTH + 1) }

    assert_response :success
    assert_conform 'LegacyError', JSON.parse(response.body)
  end

  # 範例跟 schema 脫節時 (例如欄位改名) 要能發現
  test '回應範例都符合各自的 schema' do
    checked = 0
    @document['paths'].each do |path, item|
      item.each do |method, op|
        op['responses'].each do |status, response|
          response['content'].to_h.each do |type, media|
            next unless media['examples']

            pointer = [ 'paths', path, method, 'responses', status, 'content', type, 'schema' ]
                      .map { it.gsub('~', '~0').gsub('/', '~1').gsub('{', '%7B').gsub('}', '%7D') }.join('/')
            schema = @openapi.ref("#/#{pointer}")
            media['examples'].each do |name, example|
              errors = schema.validate(example['value']).map { it['error'] }
              assert_empty errors, "#{path} #{status} 範例 #{name}"
              checked += 1
            end
          end
        end
      end
    end
    assert_operator checked, :>, 0
  end

  test 'order 說明的藏經順序與 CBETA::SORT_ORDER 一致' do
    order = @document.dig('paths', '/search/all_in_one', 'get', 'parameters').find { it['name'] == 'order' }
    assert_includes order['description'], "藏經重要性的順序：#{CBETA::SORT_ORDER.join(' ')}"
  end

  # 各 API 的 q 長度上限都寫在 spec 裡，要跟程式的常數一致
  test 'q 的 maxLength 與 MAX_QUERY_LENGTH 一致' do
    params = @document.dig('components', 'parameters').values +
             @document['paths'].values.flat_map { it.dig('get', 'parameters').to_a }
    limits = params.select { it['name'] == 'q' }.filter_map { it.dig('schema', 'maxLength') }

    assert_operator limits.size, :>, 1
    assert_equal [ ApplicationController::MAX_QUERY_LENGTH ], limits.uniq
  end

  test '/openapi.json 的版號取自 VERSION、servers 指向目前的站台' do
    get '/openapi.json'

    assert_response :success
    spec = response.parsed_body
    assert_equal Rails.configuration.x.ver, spec.dig('info', 'version')
    assert_equal [ { 'url' => 'http://www.example.com' } ], spec['servers']
    assert_empty(JSONSchemer.openapi(spec).validate.map { it['error'] })
  end

  test '/health 的回應符合 spec' do
    get '/health'

    assert_response :success
    assert_equal @document.dig('paths', '/health', 'get', 'responses', '200', 'content', 'text/plain', 'schema', 'const'),
                 response.body
  end

  test '/openapi.json 的回應符合 spec 描述的格式' do
    get '/openapi.json'

    schema = @openapi.ref('#/paths/~1openapi.json/get/responses/200/content/application~1json/schema')
    assert_empty(schema.validate(response.parsed_body).map { it['error'] })
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
