require 'json'
require_relative 'cbeta_p5a_share'

class ImportToc
  def initialize
    @xml_root = Rails.application.config.cbeta_xml
  end
  
  def import(arg)
    @inserts = []
    
    if arg.nil?
      import_all
      TocNode.delete_all
    else
      import_canon arg
      TocNode.where("work LIKE ?", "#{arg}%").delete_all
    end
        
    puts "execute SQL insert #{number_to_human(@inserts.size)} records"
    sql = 'INSERT INTO toc_nodes '
    sql += '("canon", "parent", "n", "label", "work", "file", "juan", "lb", "sort_order")'
    sql += ' VALUES ' + @inserts.join(", ")
    puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end
  
  private
  
  def get_info_from_xml(xml_path)
    doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    
    doc.search('//lb|//milestone|//mulu').each do |e|
      case e.name
      when 'lb'        then handle_lb(e)
      when 'milestone' then handle_milestone(e)
      when 'mulu'      then handle_mulu(e)
      end
    end
  end
  
  def handle_lb(e)
    unless @canon=='X' and e['ed'].start_with? 'R'
      @lb = e['n']
    end
  end
  
  def handle_milestone(e)
    if e['unit'] == 'juan'
      @juan = e['n'].to_i
    end
  end
  
  def handle_mulu(e)
    return if e['type'] == "卷"
    level = e['level'].to_i
    while @toc_stack.size > level
      @toc_stack.pop
    end
    @toc_stack[-1] += 1
    parent, n = toc_n(@toc_stack)    
    @inserts << "('#{@canon}', '#{parent}', '#{n}', '#{e.text}', '#{@work}', '#{@file}', #{@juan}, '#{@lb}', '#{@sort_order}')"
  
    @toc_stack << 0
  end
  
  def import_all
    each_canon(@xml_root) do |c|
      import_canon c
    end
  end
  
  def import_canon(canon)
    @canon = canon
    @sort_order = CBETA.get_sort_order_from_canon_id(canon)
    @previous_work = nil
    path = File.join(@xml_root, canon)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      p = File.join(path, f)
      import_vol(p)
    end
  end
  
  def import_vol(path)
    $stderr.puts "import toc #{@vol}"
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      if f.match(/^.*?n(.*?)\.xml$/)
        @work = @canon + $1
        @file = "#{@vol}n#{$1}"
        @work = 'T0220' if @work.start_with? 'T0220'
        p = File.join(path, f)
        import_work(p)
      else
        abort "work id error: #{f}"
      end
    end
  end
  
  def import_work(xml_path)
    if @work != @previous_work
      @toc_stack = [0]
    end
    get_info_from_xml(xml_path)
    @previous_work = @work
  end
  
  def toc_n(stack)
    suffix = stack.map { |i| i.to_s }
    n = @work + '.' + suffix.join('.')
    suffix.pop
    parent = @work + '.' + suffix.join('.')
    return parent, n
  end

  include CbetaP5aShare
end