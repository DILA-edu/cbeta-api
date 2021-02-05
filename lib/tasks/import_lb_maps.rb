# 讀取 CBETA XML P5a，匯入卍續藏 行號對照表

class ImportLbMaps
  
  def initialize
    @xml_base = Rails.application.config.cbeta_xml
  end
  
  def import()
    start_time = Time.now

    $stderr.puts "delete old data"
    LbMap.delete_all
    
    import_all
    
    puts "花費時間：" + Time.diff(start_time, Time.now)[:diff]
  end
  
  private
    
  def import_all()
    import_canon('X')
  end
  
  def import_canon(canon)
    folder = File.join(@xml_base, canon)
    Dir.entries(folder).sort.each do |v|
      next if v.start_with? '.'
      import_vol(v)
    end
  end
    
  def import_vol(vol)
    $stderr.puts "import_lb_maps #{vol}"
    
    @canon = vol.sub(/^([A-Z]{1,2})\d+$/, '\1')
    @vol = vol
    
    folder = File.join(@xml_base, @canon, vol)
    @inserts = []
    Dir.entries(folder).sort.each do |f|
      next unless f.end_with? '.xml'
      p = File.join(folder, f)
      import_xml_file(p)
    end
    
    sql = 'INSERT INTO lb_maps ("lb1", "lb2")'
    sql += ' VALUES ' + @inserts.join(", ")
    ActiveRecord::Base.connection.execute(sql)
  end
  
  def import_xml_file(fn)
    doc = open_xml(fn)
    doc.xpath('//lb').each do |e|
      next unless e['ed']=='X'
      lb1 = @vol + '.' + e['n']
      n = e.next_element
      next if n.nil?
      if n.name=='lb' and n['ed']!='X'
        lb2 = n['ed'] + '.' + n['n']
        @inserts << "('#{lb1}', '#{lb2}')"
      end
    end
  end
  
  def open_xml(fn)
    s = File.read(fn)

    doc = Nokogiri::XML(s)
    doc.remove_namespaces!()
    doc
  end
      
end