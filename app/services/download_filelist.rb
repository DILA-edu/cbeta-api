# frozen_string_literal: true

# 產生經號對照表 filelist_<季別>.txt 的內容, 收進全套下載的 zip。
#
#   DownloadFilelist.new(%w[T0001 X1600]).to_s
#
# 資料取自 authority catalog, 不依賴 epub: 產 docx, odt 的 zip 時, 最新的 epub 可能還沒做好。
#
# 格式沿用 CBETA 隨 epub, pdf 提供的那一份: UTF-8 無 BOM、CRLF、
# 標題列 + 分隔線 + 每筆一行 5 欄 (半形逗號前後各一個空格), 檔尾不換行。
# 下游工具 (例如 cbeta-ebook-renamer) 直接靠這個格式把經號對到經名, 改格式會弄壞它們。
class DownloadFilelist
  HEADER = ['經號 , 冊數 , 卷數 , 經名 , 作譯者', '=' * 55].freeze

  def initialize(work_ids, catalog_dir: Rails.configuration.x.work_info)
    @work_ids = work_ids
    @catalog_dir = Pathname.new(catalog_dir)
    @catalogs = {}
  end

  def to_s
    (HEADER + rows).join("\r\n")
  end

  private

  def rows
    @work_ids.sort.filter_map do |id|
      info = work_info(id)
      if info.nil?
        puts "經號對照表: authority catalog 查無 #{id}, 略過"
        next
      end

      [id, vol(info['vol']), info['juans'], info['title'], info['byline']].join(' , ')
    end
  end

  def work_info(work_id)
    canon = work_id[/\A[A-Z]+/]
    return nil if canon.nil?

    catalog(canon)[work_id]
  end

  # 一個藏經一個 json, 例: T.json
  # 缺檔是環境問題 (authority catalog 沒 checkout 或路徑設錯), 直接中止,
  # 否則會產出一份只有標題列、看起來正常的空對照表。
  def catalog(canon)
    @catalogs[canon] ||= begin
      fn = @catalog_dir.join("#{canon}.json")
      raise "經號對照表: authority catalog 找不到 #{fn}" unless fn.exist?

      JSON.load_file(fn)
    end
  end

  # 冊數不帶藏經代碼: T01 => 01; 跨冊的 T05..T07 => 05-07
  def vol(vol)
    vol.to_s.split('..').map { |v| v.sub(/\A[A-Z]+/, '') }.join('-')
  end
end
