# frozen_string_literal: true

# 提供 doc/openapi.yaml 的 JSON 版，給 public/docs.html (Scalar) 讀取。
# 不 include ApiKeyAuthentication：API 文件不納管 API key 與 rate limit。
class OpenapiController < ApplicationController
  SPEC_PATH = Rails.root.join('doc/openapi.yaml')

  def show
    # servers 依站台而不同 (root_url)
    with_release_etag(file_stamp(SPEC_PATH), root_url) { render_spec }
  end

  private

  def render_spec
    spec = MtimeCache.fetch(:openapi_spec, SPEC_PATH) { YAML.safe_load_file(SPEC_PATH, freeze: true) }
    render json: spec.merge(
      # 版號以 VERSION 檔為準，spec 檔裡不手動維護。
      'info' => spec['info'].merge('version' => Rails.configuration.x.ver),
      # 指向目前這個站台 (含 /dev、/stable 等路徑前綴)，
      # 在文件頁試打時才會打到同一個 server。
      'servers' => [ { 'url' => root_url.chomp('/') } ]
    )
  end
end
