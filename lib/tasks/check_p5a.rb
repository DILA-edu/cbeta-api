require_relative 'cbeta_p5a_share'

class CheckP5a

  def initialize
    @gaijis = CBETA::Gaiji.new(Rails.application.config.cbeta_gaiji)
    @titles = read_titles
  end
  
  def check
    @errors = ''
    @g_errors = {}
    
    src = Rails.application.config.cbeta_xml
    each_canon(src) do |c|
      @canon = c
      path = File.join(src, @canon)
      handle_canon(path)
    end

    @g_errors.keys.sort.each do |k|
      s = @g_errors[k].to_a.join(',')
      @errors += "#{k} 無缺字資料：#{s}\n"
    end
    
    if @errors.empty?
      puts "檢查完成，未發現錯誤。".green
    else
      fn = Rails.root.join('log', 'check_p5a.log')
      File.write(fn, @errors)
      puts "\n發現錯誤，請查看 #{fn}".red
    end
  end
  
  private
  
  def e_g(e)
    gid = e['ref'][1..-1]
    unless @gaijis.key? gid
      @g_errors[gid] = Set.new unless @g_errors.key? gid
      @g_errors[gid] << @basename
    end
  end
  
  def e_graphic(e)
    url = File.basename(e['url'])
    fn = File.join(Rails.configuration.x.figures, @canon, url)
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
  end
  
  def e_lem(e)
    unless e.key?('wit')
      error "lem 缺少 wit 屬性"
    end
  end

  def e_rdg(e)
    unless e.key?('wit')
      error "rdg 缺少 wit 屬性, lb: #{@lb}"
    end
  end

  def error(msg)
    s = "#{@basename} #{msg}"
    puts s
    @errors += s + "\n"
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
      @errors += "#{@basename} 含有 U+200B Zero Width Space 字元\n"
    end
    
    doc = Nokogiri::XML(s)
    if doc.errors.empty?
      doc.remove_namespaces!
      traverse(doc.root)
    else
      @errors += "錯誤: #{@basename} not well-formed\n"
    end
  end

  def handle_node(e)
    return if e.comment?
    return if e.text?
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

  def read_titles
    fn = File.join(Rails.configuration.cbeta_data, 'titles/all-title-byline.csv')
    r = {}
    CSV.foreach(fn, headers: true) do |row|
      id = row['典籍編號']
      r[id] = row['典籍名稱']
    end
    r
  end

  def traverse(e)
    e.children.each { |c| 
      handle_node(c)
    }
  end
  
  include CbetaP5aShare
end