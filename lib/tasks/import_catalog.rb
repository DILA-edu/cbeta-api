# 匯入全部: rake import:catalog
# 只匯入某個目錄: rake import:catalog[Vol-L]
#
# input:
#   * cbeta xml p5a
#   * metadata catalog
#   * table: lines

require 'cgi'
require 'pp'

class ImportCatalog
  def initialize
    @folder = File.join(Rails.application.config.cbeta_data, 'catalog')
    @xml_root = Rails.application.config.cbeta_xml
  end
  
  def import(arg)
    open_log
    
    if arg.nil?
      import_all
    else
      CatalogEntry.where("parent like ?", "#{arg}%").delete_all
      Dir["#{@folder}/*-#{arg.downcase}.xml"].each do |fn|
        import_file(fn)
      end
    end
  end
  
  private
  
  def add_alt(parent, alt, start)
    @log.puts "<p>add_alt, parent: #{parent}, alt: #{alt}, start: #{start}</p>"
    @log.puts "<blockquote>"
    data = { 
      parent: parent, 
      node_type: 'work', 
      n: serial_no(parent, start)
    }
    if alt.size <= 6
      work_id = alt
    else
      # 格式是 cbeta 行首資訊
      if alt.match(/^([A-Z])\d{2,3}n(\w{5})p(\d{4}[a-z]\d\d)$/)
        work_id = $1 + $2
        lb = $3
        work_id.sub!(/^(.*?)_$/, '\1')
        data[:lb] = lb
        line = Line.find_by(linehead: alt)
        unless line.nil?
          data[:juan_start] = line.juan 
          @log.puts "<p>juan: #{line.juan}</p>"
        end
      else
        abort "#{__LINE__} alt format error: #{alt}"
      end
    end
    data[:work] = work_id
    add_node(data)
    @log.puts "</blockquote>"
  end
  
  def add_alts(parent, alt)
    @log.puts "<p>add_alts parent: #{parent}, alt: #{alt}</p>"
    @log.puts "<blockquote>"
    alts = alt.split('+')
    i = 1
    alts.each do |a|
      add_alt(parent, a, i)
      i += 1
    end
    @log.puts "</blockquote>"
  end
  
  def add_node(data)
    @log.puts "<h3>add node, data: #{data}</h3>"
    @log.puts "<div>"
    if data.key? :label
      if data[:label].include? '(='
        unless data[:label].include? '+選錄'
          data[:node_type] = 'alt'
        end
      end
    end
    @log.puts "<p>create catalog entry, parent: #{data[:parent]}, n: #{data[:n]}</p>\n"
    @log.puts "<p>label: #{data[:label]}</p>\n" if data.key? :label
    @log.puts "<p>work: #{data[:work]}</p>\n" if data.key? :work
    begin
      CatalogEntry.create data
    rescue
      puts "Catalog Entry create error"
      puts data
      abort
    end
    @log.puts "</div>\n"
  end
    
  def add_work(parent, index, work_id, args)
    @log.puts "<h2>add work(parent: #{parent}, index: #{index}, work_id: #{work_id}</h2>"
    @log.puts "<div>"
    @log.puts "<p>args: %s</p>" % CGI.escapeHTML(args.to_s)

    if args.key? :work_object
      w = args[:work_object]
    else
      w = Work.find_by n: work_id
    end
    $stderr.puts "#{__LINE__} works table 找不到此編號：#{work_id}" if w.nil?
    type = w.alt.nil? ? 'work' : 'alt'
    
    data = { parent: parent }
    data[:n] = serial_no(parent, index)
    data[:node_type] = type
    
    if args.key? :catalog_entry
      node = args[:catalog_entry]
      if node.key? 'juan'
        juan = node['juan']
        if juan.include? '..'
          j1, j2 = juan.split '..'
          data[:juan_start] = j1.to_i
          data[:juan_end]   = j2.to_i
        else
          data[:juan_start] = juan.to_i
          data[:juan_end] = data[:juan_start]
        end
      end
      
      if node.key? 'file'
        data[:file] = node['file']
        if type == 'work'
          begin
            title = 
              if work_id.match(/^(LC|TX|Y)/)
                w.title
              else
                get_title_from_xml_file(node['file'])
              end
          rescue
            $stderr.puts "error: #{$!}"
            $stderr.puts "add_work: work_id:#{work_id}, node:#{node}"
            abort
          end
          data[:label] = "#{w.n} #{title}"
        end
      end
      if node.key? 'lb'
        data[:lb] = node['lb']
      end
    end
    
    if type == 'work'
      data[:work] = work_id
      add_node data
    else
      data[:label] = "#{w.n}(=#{w.alt}) #{w.title}"
      
      unless work_id.match(/^(LC|TX|Y)/)
        data[:label] += " (#{w.juan}卷)" unless w.juan.nil?
      end
      
      add_node data
      add_alts data[:n], w.alt
    end

    @log.puts "</div>\n"
  end
  
  def add_works(parent, node, start=1)
    work = node['work']
    
    @log.puts "<h1>add_works: #{work}</h1>\n"
    @log.puts "<div>"
    data = { parent: parent }
    i = 0
    tokens = work.split(',')
    tokens.each do |token|
      if token.include? '..'
        w1, w2 = token.split('..')
        Work.where(n: w1..w2).sort.each do |w|
          add_work(parent, start+i, w.n, work_object: w)
          i += 1
        end
      else
        add_work(parent, start+i, token, catalog_entry: node)
        i += 1
      end
    end
    @log.puts "</div>\n"
    i
  end
    
  def get_category(parent, name)
    if parent=='CBETA'
      @category = name.split[1]
    end
  end
  
  def get_title_from_xml_file(fn)
    if fn.match(/^(#{CBETA::CANON})(\d{2,3})n.*$/)
      canon = $1
      vol = $1 + $2
    end
    
    path = File.join(@xml_root, canon, vol, "#{fn}.xml")
    unless File.exist?(path)
      raise "檔案不存在：#{path}, import_catalog.rb, get_title_from_xml_file"
    end
    
    doc = File.open(path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    node = doc.at_xpath("//title[@lang='zh-Hant']")
    if node.nil?
      node = doc.at_xpath("//title")
    end
    s = node.text
    s.split.last
  end
  
  def import_all
    $stderr.puts "destroy old catalog entries"
    CatalogEntry.delete_all
    Dir["#{@folder}/*.xml"].sort.each do |fn|
      import_file(fn)
    end
  end
  
  def import_file(fn)
    unless File.exist? fn
      $stderr.puts "找不到 #{fn}"
      return
    end
    $stderr.puts "import #{fn}"

    basename = File.basename(fn, '.*')
    @canon = nil
    if basename.match(/^cat-([a-z]+)$/)
      @canon = $1.upcase
    end

    @category = nil
    
    @doc = File.open(fn) { |f| Nokogiri::XML(f) }
    @doc.do_xinclude
    @doc.remove_namespaces!
    traverse(@doc.root, @doc.root['id'])
  end
  
  def open_log
    fn = Rails.root.join('log', 'import_catalog_log.html')
    puts "log: #{fn}"
    @log = File.open(fn, 'w')
    @log.puts %(<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<style>
div { margin-left: 1em; }
</style>
</head>
<body>)
  end
  
  def serial_no(parent, i)
    # 要根據編號排序，所以要補零
    "#{parent}.%03d" % i
  end
  
  def traverse(e, parent)
    i = 0
    e.children.each do |c|
      next unless c.name == 'node'
      data = { parent: parent }
      n = c['id'] || serial_no(parent, i+1)
      get_category(parent, c['name']) if c.key? 'name'
      children_count = traverse(c, n)
      if c.key? 'name'
        if c.key? 'catalog'
          data[:n] = c['catalog']
          data[:label] = c['name']
          add_node(data)
          i += 1
          next
        elsif c.key? 'html'
          data[:node_type] = 'html'
          data[:file] = c['html']
        elsif c.key? 'work'
          add_works(n, c, 1)
        else
          next if children_count == 0
        end
        data[:n] = n
        data[:label] = c['name']
        add_node(data)        
        i += 1
      elsif c.key? 'work'
        i += add_works(parent, c, i+1)
      else
        $stderr.puts "待處理"
        $stderr.puts c
      end
    end
    i
  end  
end
