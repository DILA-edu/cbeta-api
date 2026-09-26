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

    clear_variants_cache
    puts ElapsedTime.label(t1)
  end

  private

  # search/variants 的結果會進 Rails.cache (見 SearchController#variants)，
  # key 以季別開頭但不含異體字表版本，也沒有期限。
  # 同一季中途更新異體字表時，不清掉的話會一直回傳舊結果。
  # 比對 "variants" 而不寫死 `"action" => "variants"`，
  # 以免 key 裡 params 的 inspect 格式隨 Ruby 版本改變就失效；
  # 誤刪其他 action 的少數快取也無妨。
  #
  # 只處理 Redis (staging): pattern 是 Redis glob，其他 store 的 delete_matched
  # 要 Regexp 或根本不支援 (memcached)；memory_store 則是各 process 各自一份，
  # 從 rake 清不到 web server 的快取。
  def clear_variants_cache
    if Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
      puts "清除 search/variants 快取"
      Rails.cache.delete_matched('*"variants"*')
    else
      puts "#{Rails.cache.class.name} 未自動清除，請自行清除 search/variants 快取".colorize(:red)
    end
  end

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
