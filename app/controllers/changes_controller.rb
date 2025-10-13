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

    changes = Change.where(
        params.permit(:lb, :work, :juan)
      ).select(:id, :work, :juan, :lb, :html, :ver)
    
      r = {
        num_found: changes.size,
        results: changes
      }
    my_render r
  end
end
