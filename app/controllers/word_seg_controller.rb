require 'tempfile'
class WordSegController < ApplicationController
  def index
    return unless params.key? :t
    
    if params[:t].size == 1
      render plain: params[:t]
      return
    end

    r = WordSegService.new.run(params[:t])
    if r.success?
      render plain: r.result
    else
      render plain: r.errors
    end
  end

  def run
    if params[:payload].nil?
      render json: { 
        error: { 
          code: 400,
          message: "缺少 payload 參數"
        }
      }
      return
    end

    if params[:payload].size == 1
      render json: { segmented: [params[:payload]] }
      return
    end

    r = WordSegService.new.run(params[:payload])
    if r.success?
      puts r.result
      r.result.sub!(/^\//, '')
      render json: { segmented: r.result.split('/') }
    else
      render json: { 
        error: { message: r.errors }
      }
    end
  end
end
