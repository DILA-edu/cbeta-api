namespace :import do
  desc "匯入 異體字表"
  task :vars => :environment do
    ImportVars.new.import
  end
end

class ImportVars  
  def initialize
    @folder = Rails.application.config.cbeta_data
    # 只查 text index: 與 SearchController#exist_in_cbeta 不同，
    # 這裡刻意不查 notes / titles，否則會改變 Variant 表要保留哪些異體字。
    @search = CbetaSearch::SearchService.new(index: CbetaSearch::TextIndex)
  end
  
  def import
    t1 = Time.now
    puts "清除舊資料"
    Variant.delete_all
    
    @total = 0
    @inserts = []
    read_variants

    puts "insert_all"
    Variant.insert_all(@inserts)

    puts "Variant records: #{number_with_delimiter(Variant.count)}"
    puts "total vars: #{number_with_delimiter(@total)}"
    puts ElapsedTime.label(t1)
  end
  
  private

  def cbeta_pua(s)
    return s unless s.start_with?('CB')
    CBETA.pua(s)
  end
  
  def exist_in_cbeta(q)
    query = CbetaSearch::Query.new(type: :phrase, raw: q, phrase: q.downcase)
    @search.exist?(query, params: {})
  end

  def read_variants
    fn = File.join(@folder, 'variants', 'vars-for-cbdata.json')
    puts "read #{fn}"
    variants = JSON.parse(File.read(fn))

    # 先把所有候選字收齊，一次批次問 Elasticsearch。
    # 逐字問要發幾萬次 HTTP 請求，會把 ephemeral port 用光。
    candidates = variants.each_value.flat_map { |v| v.split(',') }.uniq
    puts "查詢 #{number_with_delimiter(candidates.size)} 個候選字是否出現在 CBETA"
    exists = @search.exist_all?(candidates)

    variants.each_pair do |k, v|
      k1 = cbeta_pua(k)

      # 去掉 CBETA 沒用到的字
      vars = v.split(',').select { |c| exists[c] }
      next if vars.empty?

      vars.map! { |c| cbeta_pua(c) }

      @total += vars.size
      s = vars.join(',')
      @inserts << { k: k1, vars: s }
    end
  end  
end
