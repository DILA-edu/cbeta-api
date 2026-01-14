class ExportController < ApplicationController
  before_action :init

  def init
    @use_cache = params.key?(:cache) ? (params[:cache]=='1') : true
  end
  
  def all_creators2
    fn = Rails.root.join('data', 'all-creators-with-alias.json')
    r = {}

    if File.file?(fn)
      s = File.read(fn)
      data = JSON.parse(s)

      if referer_cn?
        data.delete('A023393') # 印順法師
        data.delete('A004819') # 太虛
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
