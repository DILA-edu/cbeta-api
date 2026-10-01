require 'tempfile'
class WordSegController < ApplicationController
  include ApiKeyAuthentication

  def index
    unless params.key? :t
      render plain: '缺少 t 參數'
      return
    end
    
    if params[:t].size == 1
      render plain: params[:t]
      return
    end

    r = WordSegService.new.run(params[:t])
    if r.success?
      render plain: r.result
    else
      render plain: word_seg_failed(r)
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
        error: { code: 500, message: word_seg_failed(r) }
      }
    end
  end

  private

  # 錯誤細節 (暫存檔路徑、斷詞程式的 stderr) 只寫進 log
  def word_seg_failed(result)
    logger.error "WordSegService 失敗: #{result.errors}"
    '斷詞失敗'
  end
end
