class ImportGaiji
  def initialize
    @folder = Rails.application.config.cbeta_gaiji
  end
  
  def import
    puts "delete old gaijis"
    Gaiji.delete_all

    fn = File.join(@folder, 'cbeta_gaiji.json')
    gaijis = JSON.parse(File.read(fn))
    
    inserts = []
    gaijis.each do |k,v|
      if v.key? 'composition'
        pua = v['pua'].delete_prefix('U+').to_i(16)
        pua = [pua].pack 'U'
        inserts << { cb: k, zzs: v['composition'], pua: pua }
      end
    end
    
    puts "insert new gaijis"
    Gaiji.insert_all(inserts)

    puts "Gaiji records: #{number_with_delimiter(Gaiji.count)}"
  end
    
end
