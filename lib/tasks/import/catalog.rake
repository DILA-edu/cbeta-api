namespace :import do
  desc "匯入部類目錄"
  task catalog: :environment do
    importer = ImportCatalog.new
    importer.import
  end
end

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
  WORK_REGEX = /#{CBETA::CANON}(?:#{CBETA::WORK_PART})/ # T0001
  VOL_REGEX = /#{CBETA::CANON}\d{2,3}/ # T01

  # T0220_576
  # T0310_017..018
  JUAN_REGEX = /\A
    (
      #{CBETA::CANON}
      (?:
        #{CBETA::WORK_PART}
      )
    )
    _(\d{3})
    (?:\.\.(\d{3}))?
  \z/x

  def initialize
    @catalog_base = "https://raw.githubusercontent.com/heavenchou/cbwork-bin/refs/heads/master/cbreader2X"
    @xml_root = Rails.application.config.cbeta_xml
  end
  
  def import
    open_log
    $stderr.puts "destroy old catalog entries"
    CatalogEntry.delete_all
    import_file("bulei/bulei.txt", "CBETA", label: "部類目錄")
    import_file("nav/advance_nav.txt", "orig", label: "原書目錄")
  end
  
  private
  
  def import_file(rel_path, id, label:)
    @log.puts "<p>import_file: #{rel_path}</p>\n"
    $stderr.puts "import #{rel_path}"
    add_node(parent: "root", n: id, label:)

    @catalog = id
    @canon = nil
    @category = nil
    
    catalog_url = File.join(@catalog_base, rel_path)
    xml = read_catalog_text(catalog_url)
    @doc = Nokogiri::XML(xml)
    @level = 0
    traverse(@doc.root, id)
  end
  
  def read_catalog_text(catalog_url)
    puts "Get #{catalog_url}"
    response = Faraday.get(catalog_url)

    if response.status == 200
      bn = File.basename(catalog_url, ".*")
      dest = Rails.root.join("log", "catalog-#{bn}.txt")
      puts "write #{dest}"
      File.write(dest, response.body)
    else
      raise "Failed to fetch file: #{catalog_url}, response status: #{response.status}"
    end    

    xml = "<root>"
    @level = 0
    response.body.lines.each do |line|
      line.rstrip!
      line =~ /\A(\t*)(.*)\z/
      level = $1.size + 1
      text = $2.gsub(/&(CB|M)\d+;/, '●')
      xml << close_node(level)
      prefix = "  " * level
      xml << %(\n#{prefix}<node text="#{text}">)
      @level += 1
    end
    xml << close_node(1)
    xml << "</root>"

    dest = Rails.root.join("log", "catalog-#{bn}.xml")
    puts "write #{dest}"
    File.write(dest, xml)
    xml
  end

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
    data[:sort] = index
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
        data[:label] << " (#{w.juan}卷)" unless w.juan.nil?
      end
      
      add_node data
      add_alts data[:n], w.alt
    end

    @log.puts "</div>\n"
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
    node = doc.at_xpath("//title[@level='m']")
    if node.nil?
      node = doc.at_xpath("//title")
    end
    s = node.text
    s.split.last
  end

  def close_node(level)
    r = ""
    while level <= @level
      r << "</node>"
      @level -= 1
    end
    r
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
  
  def serial_no(parent, i, node: nil)
    canon = nil

    # 原書目錄 各藏 第一層 要用 Vol-T, Vol-X 等等
    if node && @catalog == "orig" && @level < 4
      if node["text"] =~ /^(#{CBETA::CANON}) /
        canon = $1
      end
    end

    if canon
      "orig-#{canon}"
    else
      "#{parent}.%03d" % i  # 要根據編號排序，所以要補零
    end
  end
  
  def traverse(e, parent)
    @level += 1
    i = 1
    e.children.each do |c|
      next unless c.name == 'node'
      n = serial_no(parent, i, node: c)
      @category = c["text"].split[1] if parent=='CBETA'

      children_count = traverse(c, n)
      @log.puts "<p>children_count: #{children_count}</p>\n"

      if c.children.size > 0
        add_node(parent:, n:, label: c["text"], sort: i)
        i += 1
        next
      end

      case c["text"]
      when /^#{CBETA::CANON}$/
        i += handle_canon_node(parent, node: c, start: i)
      when / /
        s1, _, s2 = c["text"].partition(/ /)
        if s1.end_with?(".htm")
          add_node(parent:, node_type: "html", file: s1, n:, label: s2, sort: i)
        elsif s1 =~ JUAN_REGEX
          handle_juan_node(parent, node: c, start: i)
        end
        i += 1
      else
        i += handle_list(parent, node: c, start: i)
      end
    end
    @level -= 1
    i
  end

  def handle_canon_node(parent, node:, start:)
    canon = node["text"]
    i = 0
    Work.where(canon:).order(:n).each do |w|
      add_work(parent, start+i, w.n, work_object: w)
      i += 1
    end
    i
  end

  def handle_juan_node(parent, node:, start:)
    s1, _, label = node["text"].partition(/ /)

    if s1 =~ JUAN_REGEX
      work = $1
      j1 = $2.to_i
    else
      raise "格式不符: #{node.to_xml}"
    end

    add_node(
      parent:,
      n: serial_no(parent, start),
      label:,
      work:,
      juan_start: j1,
      sort: start
    )
  end

  def handle_list(parent, node:, start:)
    list = node["text"].split(",")
    i = 0
    list.each do |item|
      p1 = item
      p1, p2 = item.split("..") if item.include?("..") # 範圍
      if p1 =~ WORK_REGEX # T0262..T0277
        i += work_range(parent, p1, p2, start: start+i)
      elsif p1 =~ VOL_REGEX
        i += vol_range(parent, p1, p2, start: start+i)
      else
        raise "未知格式: #{p1}"
      end
    end
    i
  end

  def vol_range(parent, v1, v2, start:)
    i = 0
    v2 = v1 if v2.nil?

    Work.where(vol: v1..v2).order(:n).each do |w|
      add_work(parent, start+i, w.n, work_object: w)
      i += 1
    end

    i
  end

  def work_range(parent, w1, w2, start:)
    i = 0
    w2 = w1 if w2.nil?

    Work.where(n: w1..w2).order(:n).each do |w|
      add_work(parent, start+i, w.n, work_object: w)
      i += 1
    end

    i
  end
end
