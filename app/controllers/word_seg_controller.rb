require 'tempfile'
class WordSegController < ApplicationController

  def index
    return unless params.key? :t
    r = WordSegService.new.run(params[:t])
    if r.success?
      render plain: r.result
    else
      render plain: r.errors
    end
  end

end