namespace :import do
  task :goto_abbrs => :environment do
    importer = ImportGotoAbbrs.new
    importer.import
  end
end

# 讀取 CBETA XML P5a，匯入卍續藏 行號對照表
class ImportGotoAbbrs
  
  TABLE = 'goto_abbrs'
  
  def initialize
    @base = Rails.application.config.cbeta_data
  end
  
  def import()
    fn = File.join(@base, 'goto', 'goto-list.txt')
    inserts = []
    File.foreach(fn) do |line|
      line.chomp!
      if line.match(/^(.*?)=(.*)$/)
        inserts << { abbr: $1, ref: $2 }
      end
    end
    
    # 包在 transaction 裡: 中途 abort / 例外時保留舊資料, 不會留下空表或只匯一半
    GotoAbbr.transaction do
      GotoAbbr.delete_all
      GotoAbbr.insert_all(inserts)
    end
    s = number_with_delimiter(GotoAbbr.count)
    puts "GotoAbbr records: #{s}"
  end

end
