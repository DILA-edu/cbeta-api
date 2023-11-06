# 讀取 CBETA XML P5a，匯入卍續藏 行號對照表

class ImportGotoAbbrs
  
  TABLE = 'goto_abbrs'
  
  def initialize
    @base = Rails.application.config.cbeta_data
  end
  
  def import()
    GotoAbbr.delete_all
    
    fn = File.join(@base, 'goto', 'goto-list.txt')
    @inserts = []
    File.foreach(fn) do |line|
      line.chomp!
      if line.match /^(.*?)=(.*)$/
        @inserts << "('#{$1}', '#{$2}')"
      end
    end
    
    sql = %[INSERT INTO #{TABLE} ("abbr", "ref")]
    sql << ' VALUES ' + @inserts.join(", ")
    ActiveRecord::Base.connection.execute(sql)
  end

end
