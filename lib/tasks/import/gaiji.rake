namespace :import do
  task :gaiji => :environment do
    importer = ImportGaiji.new
    importer.import
  end
end

class ImportGaiji
  def initialize
    @folder = Rails.application.config.cbeta_gaiji
  end
  
  def import
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
    
    # 包在 transaction 裡: 中途 abort / 例外時保留舊資料, 不會留下空表或只匯一半
    Gaiji.transaction do
      puts "delete old gaijis"
      Gaiji.delete_all
      puts "insert new gaijis"
      Gaiji.insert_all(inserts)
    end

    puts "Gaiji records: #{number_with_delimiter(Gaiji.count)}"
  end
    
end
