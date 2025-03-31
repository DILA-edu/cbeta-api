require 'cbeta'
require_relative 'cbeta_p5a_share'

class CheckP5a

  def initialize(xml_root: nil, figures: nil, log: nil)
    @gaijis = CBETA::Gaiji.new
    @xml_root = xml_root || Rails.configuration.cbeta_xml
    @figures = figures || Rails.configuration.x.figures
    @log = log || Rails.root.join('log', 'check_p5a.log')
  end
  
  def check
    @errors = ''
    @g_errors = {}
    puts "xml: #{@xml_root}"
    each_canon(@xml_root) do |c|
      @canon = c
      path = File.join(@xml_root, @canon)
      handle_canon(path)
    end

    @g_errors.keys.sort.each do |k|
      s = @g_errors[k].to_a.join(',')
      @errors << "#{k} 無缺字資料，出現於：#{s}\n"
    end
    
    if @errors.empty?
      puts "檢查完成，未發現錯誤。".green
    else
      File.write(@log, @errors)
      puts "\n發現錯誤，請查看 #{@log}"
    end
  end
  
  private

  def chk_text(node)
    return if node.text.strip.empty?
    if node.parent.name == 'div'
      error "lb: #{@lb}, text: #{node.text.inspect}", type: "[E02] 文字直接出現在 div 下"
    end
  end

  def e_g(e)
    gid = e['ref'][1..-1]
    unless @gaijis.key? gid
      @g_errors[gid] = Set.new unless @g_errors.key? gid
      @g_errors[gid] << @basename
    end
  end
  
  def e_graphic(e)
    url = File.basename(e['url'])
    fn = File.join(@figures, @canon, url)
    unless File.exist? fn
      error "圖檔 #{url} 不存在"
    end
  end
  
  def e_lb(e)
    return if e['type']=='old'
    unless e['n'].match(/^[a-z\d]\d{3}[a-z]\d+$/)
      error "lb format error: #{e['n']}"
    end

    @lb = e['n']
    ed_lb = "#{e['ed']}#{@lb}"
    if @lbs.include? ed_lb
      unless e['ed'].start_with?('R')
        error "lb: #{@lb}, ed: #{e['ed']}", type: "[E01] 行號重複"
      end
    else
      @lbs << ed_lb
    end
  end
  
  def e_lem(e)
    unless e.key?('wit')
      error "lem 缺少 wit 屬性"
    end
  end

  def e_rdg(e)
    return if e['type'] == 'cbetaRemark'
    unless e.key?('wit')
      error "rdg 缺少 wit 屬性, lb: #{@lb}"
    end
  end

  def error(msg, type: nil)
    s = ''
    s << "#{type}: " unless type.nil?
    s << "#{@basename}, #{msg}"
    puts s
    @errors << s + "\n"
  end
  
  def handle_canon(folder)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      $stderr.puts @vol + ' '
      path = File.join(folder, @vol)
      handle_vol(path)
    end
  end
  
  def handle_file(fn)
    @basename = File.basename(fn)
    
    s = File.read(fn)
    if s.include? "\u200B"
      @errors << "#{@basename} 含有 U+200B Zero Width Space 字元\n"
    end
    
    doc = Nokogiri::XML(s)
    if doc.errors.empty?
      doc.remove_namespaces!
      @lbs = Set.new
      traverse(doc.root)
    else
      @errors << "錯誤: #{@basename} not well-formed\n"
    end
  end

  def handle_node(e)
    case e.name
    when 'g'       then e_g(e)
    when 'graphic' then e_graphic(e)
    when 'lb'      then e_lb(e)
    when 'lem'     then e_lem(e)
    when 'rdg'     then e_rdg(e)
    else traverse(e)
    end
  end
  
  def handle_vol(folder)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      path = File.join(folder, f)
      handle_file(path)
    end
  end

  def traverse(e)
    e.children.each { |c| 
      if c.text?
        chk_text(c)
      elsif e.element?
        handle_node(c)
      end
    }
  end
  
  include CbetaP5aShare
end
