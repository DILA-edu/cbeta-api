require 'open3'
class ChineseToolsController < ApplicationController
  def sc2tc
    cmd = 'opencc -c s2tw'
    a = Open3.capture2(cmd, stdin_data: params[:q])
    render plain: a[0]
  end
end
