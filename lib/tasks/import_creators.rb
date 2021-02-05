# import byline, creators from cbeta metadata

require 'pp'

class ImportCreators
  def initialize
    @folder = File.join(Rails.application.config.cbeta_data, 'creators', 'creators-by-canon')
  end
  
  def import(canon)
    if canon.nil?
      import_all_canon
      import_all_creators
    else
      canon.upcase!
      fn = "#{@folder}/#{canon}.json"
      import_canon(fn)
    end
  end
  
  private
  
  def import_all_canon
    Dir["#{@folder}/*.json"].each do |f|
      import_canon(f)
    end
  end
  
  def import_all_creators
    fn = File.join(Rails.application.config.cbeta_data, 'creators', 'all-creators.json')
    creators = JSON.parse(File.read(fn))
    inserts = []
    creators.each do |a|
      inserts << "('#{a[0]}', '#{a[1]}')"
    end
    $stderr.puts "execute SQL insert #{number_to_human(inserts.size)} records"
    sql = 'INSERT INTO people '
    sql += '("id2", "name")'
    sql += ' VALUES ' + inserts.join(", ")
    $stderr.puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end

  def import_canon(fn)
    $stderr.puts "import_creators #{fn}"
    s = File.read(fn)
    creators = JSON.parse(s)
    creators.each_pair do |k,v|
      next unless v.key? 'creators'
      w = Work.find_by n: k
      next if w.nil?
      w.byline   = v['byline']
      w.creators = v['creators']
      w.creators_with_id = v['creators_with_id']
      w.save
    end
  end
  
end