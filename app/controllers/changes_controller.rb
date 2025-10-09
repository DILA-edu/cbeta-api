class ChangesController < ApplicationController
  def index
    changes = Change.where(lb: params[:lb]).select(:id, :lb, :html, :ver)
    r = {
        num_found: changes.size,
        results: changes
      }
    my_render r
  end  
end
