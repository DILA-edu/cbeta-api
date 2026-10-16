class ExportController < ApplicationController
  include ApiKeyAuthentication

  before_action :init

  def init
    @use_cache = params.key?(:cache) ? (params[:cache]=='1') : true
  end
  
  def all_creators2
    fn = Rails.root.join('data', 'all-creators-with-alias.json')
    r = {}

    if File.file?(fn)
      data = MtimeCache.fetch(:all_creators2, fn) { JSON.parse(File.read(fn), freeze: true) }

      if referer_cn?
        # 快取的 data 是共用的, 不可就地 delete
        data = data.except(
          'A023393', # 印順法師
          'A004819'  # 太虛
        )
      end

      r[:num_found] = data.size
      r[:results] = data
    else
      r[:error] = { code: 500, message: "File not found: #{fn}" } 
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
      r[:error] = { code: 500, message: "File not found: #{fn}" } 
    end

    my_render(r)
  end  
end
