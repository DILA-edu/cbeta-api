# DocuSky 的作業流程：
#   會先透過 [TextRef](https://textref.org/) 登錄的 metadata 取得 CBETA 所有文本書目的 metadata。
#   將 metadata 的書目顯示給使用者看，讓使用者選擇要下載哪些經書。
#   透過 CBETA API 下載經書的 DocuXml
class TextrefController < ApplicationController
  def meta
  end

  def data
    headers = %w(primary_id title dynasty author edition fulltext_read fulltext_search fulltext_download image)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << headers
      Work.where(alt: nil).order(:n).each do |w|
        csv << [
          w.n, 
          w.title, 
          w.time_dynasty,
          w.creators,
          Canon.find_by(id2: w.canon).name,
          'y', 'y', 'y', 'n'
        ]
      end
    end

    send_data(
      csv_data,
      filename: 'data.csv', # suggests a filename for the browser to use.
      type: :csv,  # specifies a "text/csv" HTTP content type
    )
  end
end
