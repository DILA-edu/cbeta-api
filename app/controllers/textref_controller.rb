# DocuSky 的作業流程：
#   會先透過 [TextRef](https://textref.org/) 登錄的 metadata 取得 CBETA 所有文本書目的 metadata。
#   將 metadata 的書目顯示給使用者看，讓使用者選擇要下載哪些經書。
#   透過 CBETA API 下載經書的 DocuXml
class TextrefController < ApplicationController
  include ApiKeyAuthentication

  def meta
  end

  def data
    with_release_etag { render_data }
  end

  private

  def render_data
    headers = %w(primary_id title dynasty author edition fulltext_read fulltext_search fulltext_download image)

    # canon 只有幾十筆, 先全部載入, 免得每部佛典查一次。
    # 同一 id2 若有多筆, 取 id 最小的 (與原本 find_by 相同)。
    canons = Canon.order(:id).each_with_object({}) { |c, h| h[c.id2] ||= c }

    csv_data = CSV.generate(headers: true) do |csv|
      csv << headers
      Work.where(alt: nil).order(:n).each do |w|
        canon = canons[w.canon]
        msg = "TextrefController::data, canon id '#{w.canon}' 在 Canon model 裡找不到"
        raise CbetaError.new(500), msg if canon.nil?
        csv << [
          w.n, 
          w.title, 
          w.time_dynasty,
          w.creators,
          canon.name,
          'y', 'y', 'y', 'n'
        ]
      end
    end

    send_data(
      csv_data,
      filename: 'data.csv', # suggests a filename for the browser to use.
      type: :csv,  # specifies a "text/csv" HTTP content type
    )
  rescue CbetaError => e
    my_render_error(e.code, $!)
  end
end
