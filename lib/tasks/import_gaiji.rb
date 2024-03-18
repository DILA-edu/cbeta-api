class ImportGaiji
  def initialize
    @folder = Rails.application.config.cbeta_gaiji
  end
  
  def import
    $stderr.puts "destroy old gaijis"
    Gaiji.destroy_all
    fn = File.join(@folder, 'cbeta_gaiji.json')
    gaijis = JSON.parse(File.read(fn))
    
    @inserts = []
    gaijis.each do |k,v|
      if v.key? 'composition'
        pua = v['pua'].delete_prefix('U+').to_i(16)
        pua = [pua].pack 'U'
        @inserts << "('#{k}', '#{v['composition']}', '#{pua}')"
      end
    end
    
    $stderr.puts "執行 SQL insert 命令：#{number_to_human(@inserts.size)} records"
    sql = 'INSERT INTO gaijis '
    sql << '("cb", "zzs", "pua")'
    sql << ' VALUES ' + @inserts.join(", ")
    $stderr.puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end
    
end
