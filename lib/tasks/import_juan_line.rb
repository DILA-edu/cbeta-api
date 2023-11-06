require 'json'

# Prerequisites:
#   * data-static/uuid/juans.json
class ImportJuanLine
  def initialize
    @juan_uuids = read_uuid
  end
  
  def import
    $stderr.puts "delete all records from table: juan_lines"
    $stderr.puts Benchmark.measure {
      JuanLine.delete_all
    }
    @inserts = []
    @uuids = Set.new
    @vol_lbs = Set.new

    folder = Rails.root.join('data', 'juan-line')
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      @canon = f
      path = File.join(folder, f)
      import_canon(path)
    end

    $stderr.puts "#{__LINE__} execute SQL insert #{number_to_human(@inserts.size)} records"
    sql = 'INSERT INTO juan_lines '
    sql << '("vol", "work", "juan", "lb", "lb_end", "uuid", "content_uuid")'
    sql << ' VALUES ' + @inserts.join(", ")
    $stderr.puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end
  
  private
    
  def import_canon(folder)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      @work = File.basename(f, '.json')
      path = File.join(folder, f)
      import_file(path)
    end
  end
  
  def import_file(fn)
    s = File.read(fn)
    juans = JSON.parse(s)
    juans.each_pair do |k, v|
      id = "#{@work}_%03d" % k.to_i
      abort "#{id} 在 data-static/uuid/juans.json 不存在" unless @juan_uuids.key? id
      
      uuid1 = @juan_uuids[id]['juan_uuid']
      uuid2 = @juan_uuids[id]['content_uuid']

      if @uuids.include?(uuid1)
        abort "UUID 重複: #{uuid1}"
      else
        @uuids << uuid1
      end
      
      # 某些 lb 不是數字開頭，例如 Y01n0001_pa001a02
      # a001 的排序會變成在 0001 的後面
      # 把它改成 0000a001 讓排序變成在 0001 前面
      lb = v['lb_begin']
      lb = "0000#{lb}" unless lb.match(/^\d/)

      vol_lb = v['vol'] + lb
      if @vol_lbs.include?(vol_lb)
        abort "發生錯誤：vol+lb 重複： vol: #{v['vol']}, lb: #{lb}".red
      else
        @vol_lbs << vol_lb
      end
      
      @inserts << "('#{v['vol']}', '#{@work}', #{k}, "\
        "'#{lb}', '#{v['lb_end']}', '#{uuid1}', '#{uuid2}')"
    end
  end
  
  def read_uuid
    fn = Rails.root.join('data-static', 'uuid', 'juans.json')
    s = File.read(fn)
    JSON.parse(s)
  end

end
