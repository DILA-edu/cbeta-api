namespace :search_xml do
  desc "轉出 titles.xml（供 Elasticsearch 的 titles index 使用）"
  task :titles => :environment do
    SearchXmlTitles.new.run
  end
end

require_relative 'search-xml-share'

# 讀 Work model，產生 xml 給搜尋引擎做 index。
# 目前的消費者是 Elasticsearch 的 titles index（見 CbetaSearch::TitlesIndex），
# 產生 titles.xml，供 Elasticsearch 的 titles index 匯入。
class SearchXmlTitles
  include SearchXmlShare

  # get_info_from_work 回傳的欄位裡，titles index 用不到的。
  # title 也排除: 經名在這裡是被搜尋的 content 欄位，不另存一份。
  EXCLUDE = %i[title byline work_type alt juan_list juan_start].freeze

  def initialize
    @dynasty_labels = read_dynasty_labels
  end

  def run
    @id = 0
    
    folder = Rails.root.join('data', 'search-xml')
    FileUtils.mkpath(folder)
    
    fn = Rails.root.join(folder, 'titles.xml')
    @fo = open_xml(fn)
    
    max = 0
    Work.find_each do |w|
      # 如果有 替代佛典
      unless w.alt.blank?
        # 如果這部佛典在 CBETA 裡沒有全文，就不將 title 列入搜尋
        # 例如 JA088 不加入，而 JB277 要加入
        f = XmlFile.find_by work: w.n
        next if f.nil?
      end

      @id += 1
      max = [max, w.title.size].max
      data = {
        work: w.n,
        content: w.title,
        canon: w.canon,
        canon_order: CBETA.get_sort_order_from_canon_id(w.canon)
      }
      # 補上朝代、部類、作譯者、年代，讓 /search/title 也能用限制搜尋範圍的參數。
      info = get_info_from_work(w.n, exclude: EXCLUDE)
      data.merge!(info.except(*EXCLUDE)) unless info.nil?
      write_xml(@fo, data)
    end
    puts "title 最長: #{max}"
    
    close_xml(@fo)
    puts "output file: #{fn}"
  end
  
  private
  
  def close_xml(f)
    f.write '</sphinx:docset>'
    f.close
  end

  def open_xml(fn)
    f = File.open(fn, 'w')
    f.puts %(<?xml version="1.0" encoding="utf-8"?>\n)
    f.puts "<sphinx:docset>\n"
    f
  end

  def write_xml(f, data)
    s = "<sphinx:document id='#{@id}'>\n"
    
    data.each_pair do |k,v|
      next if v.nil?

      s << "<#{k}>#{v.to_s.encode(xml: :text)}</#{k}>\n"
    end
    
    s << "</sphinx:document>\n"
    f.puts s
  end

end
