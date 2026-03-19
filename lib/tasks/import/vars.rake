namespace :import do
  desc "匯入 異體字表"
  task :vars => :environment do
    ImportVars.new.import
  end
end

class ImportVars  
  def initialize
    @folder = Rails.application.config.cbeta_data
    @index = Rails.configuration.x.se.index_text
  end
  
  def import
    puts "清除舊資料"
    Variant.delete_all
    
    @total = 0
    @inserts = []
    read_variants

    puts "insert_all"
    Variant.insert_all(@inserts)

    puts "Variant records: #{number_with_delimiter(Variant.count)}"
    puts "total vars: #{number_with_delimiter(@total)}"
  end
  
  private

  def cbeta_pua(s)
    return s unless s.start_with?('CB')
    CBETA.pua(s)
  end
  
  def exist_in_cbeta(q)
    select = %(SELECT id FROM #{@index} WHERE MATCH('"#{q}"') LIMIT 0, 1)
    result = @mysql_client.query(select)
    
    if result.size == 0
      return false
    else
      return true
    end    
  end
  
  def filter(terms)
    r = []
    terms.each do |t|
      r << t if exist_in_cbeta(t)
    end
    r
  end

  def read_variants
    @manticore = ManticoreService.new
    @mysql_client = @manticore.open

    fn = File.join(@folder, 'variants', 'vars-for-cbdata.json')
    puts "read #{fn}"
    variants = JSON.parse(File.read(fn))

    variants.each_pair do |k, v|
      k1 = cbeta_pua(k)
      vars = v.split(',')

      # 去掉 CBETA 沒用到的字
      vars.delete_if { |c| not exist_in_cbeta(c) }
      next if vars.empty?

      vars.map! { |c| cbeta_pua(c) }

      @total += vars.size
      s = vars.join(',')
      @inserts << { k: k1, vars: s }
    end

    @manticore.close
  end  
end
