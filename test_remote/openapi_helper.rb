require 'json_schemer'
require 'yaml'

# test_remote/test_openapi_*.rb 共用: 以 OpenAPI spec 驗證線上 API 的回應。
# 預設讀 doc/openapi.yaml; 尚未併入的 spec 片段可用 OPENAPI_SPEC 指定合併後的檔案。
module OpenapiHelper
  SPEC_PATH = ENV.fetch('OPENAPI_SPEC', File.expand_path('../doc/openapi.yaml', __dir__))
  OPENAPI = JSONSchemer.openapi(YAML.safe_load_file(SPEC_PATH))

  # path 為 spec 裡的 path (例: '/search/all_in_one')
  def self.response_schema(path, status: '200', method: 'get')
    # JSON pointer 放在 URI fragment 裡, path 參數的 {} 要 percent-encode
    pointer = path.gsub('~', '~0').gsub('/', '~1').gsub('{', '%7B').gsub('}', '%7D')
    OPENAPI.ref("#/paths/#{pointer}/#{method}/responses/#{status}/content/application~1json/schema")
  end

  private

  # url 為實際呼叫的網址 (不含 $api)，path 為 spec 裡的 path; 兩者不同時 (有 path 參數) 才需要傳 path。
  def assert_conform(url, params = {}, path: "/#{url}")
    r = get_json(url, params)
    errors = OpenapiHelper.response_schema(path).validate(r).map { it['error'] }
    assert_empty errors, "#{url} #{params.inspect} 的回應不符合 #{SPEC_PATH}:\n#{errors.join("\n")}"
    r
  end
end
