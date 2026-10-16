require 'open3'
class ChineseToolsController < ApplicationController
  include ApiKeyAuthentication

  def sc2tc
    if tool_input_too_long?(params[:q])
      render plain: tool_input_length_error('q'), status: :bad_request
      return
    end

    cmd = 'opencc -c s2tw'
    a = Open3.capture2(cmd, stdin_data: params[:q])
    render plain: a[0]
  end
end
