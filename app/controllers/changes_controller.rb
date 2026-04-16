# frozen_string_literal: true

class ChangesController < ApplicationController
  def index
    if params[:lb].blank? and params[:work].blank?
      my_render(error: "lb 參數 與 work 參數 不能都是空的。")
      return
    end

    if params.key?(:juan)
      if params.key?(:work)
        params[:juan] = params[:juan].to_i 
      else
        my_render(error: "必須有 work 參數，才能指定 juan 參數。")
        return
      end
    end

    @changes = Change.where(
        params.permit(:lb, :work, :juan)
      ).select(
        :id, :work, :juan, :lb, :html, :ver, :del_chars, :ins_chars
      ).order(ver: :desc)
    
    request.format = "json" unless params[:format]
    respond_to do |format|
      format.html { index_html }
      format.json { 
        r = {
          num_found: @changes.size,
          results: @changes
        }
        my_render r
      }
    end
  end

  private

  def index_html
    ver = nil
    html = +""
    @changes.each do |c|
      if ver != c.ver
        html << "<h2>#{c.ver}</h2>\n"
        ver = c.ver
      end
      html << "#{c.lb}║#{c.html}<br>\n"
    end
    render plain: html    
  end
end
