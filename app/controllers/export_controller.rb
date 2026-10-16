class ExportController < ApplicationController
  include ApiKeyAuthentication

  before_action :init

  def init
    @use_cache = params.key?(:cache) ? (params[:cache]=='1') : true
  end
  
  def all_creators2
    fn = Rails.root.join('data', 'all-creators-with-alias.json')
    with_release_etag(file_stamp(fn)) { render_all_creators2(fn) }
  end

  private def render_all_creators2(fn)
    r = {}

    if File.file?(fn)
      data = MtimeCache.fetch(:all_creators2, fn) { JSON.parse(File.read(fn), freeze: true) }

      r[:num_found] = data.size
      r[:results] = data
    else
      # 不回傳伺服器的絕對路徑
      r[:error] = { code: 500, message: "File not found: #{fn.relative_path_from(Rails.root)}" }
    end

    my_render(r)
  end

  def all_creators3
    fn = Rails.root.join('data', 'all-creators-with-alias3.json')
    r = {}

    if File.file?(fn)
      s = File.read(fn)
      data = JSON.parse(s)
      r[:num_found] = data.size
      r[:results] = data
    else
      # 不回傳伺服器的絕對路徑
      r[:error] = { code: 500, message: "File not found: #{fn.relative_path_from(Rails.root)}" }
    end

    my_render(r)
  end  
end
