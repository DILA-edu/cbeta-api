# frozen_string_literal: true

# 提供 doc/openapi.yaml 的 JSON 版，給 public/docs.html (Scalar) 讀取。
# 不 include ApiKeyAuthentication：API 文件不納管 API key 與 rate limit。
class OpenapiController < ApplicationController
  SPEC_PATH = Rails.root.join('doc/openapi.yaml')

  def show
    spec = YAML.safe_load_file(SPEC_PATH)
    # 版號以 VERSION 檔為準，spec 檔裡不手動維護。
    spec['info']['version'] = Rails.configuration.x.ver
    # 指向目前這個站台 (含 /dev、/stable 等路徑前綴)，
    # 在文件頁試打時才會打到同一個 server。
    spec['servers'] = [ { 'url' => root_url.chomp('/') } ]
    render json: spec
  end
end
