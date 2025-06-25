# 檢查 xml4docx 檔案 是否正確
class CheckXMLForDocx
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @styles = YAML.load_file(fn)

    fn = Rails.root.join('log', 'check_xml4docx.log')
    @log = File.open(fn, 'w')

    rnc = Rails.root.join('data-static', 'schema', 'xml4docx.rnc')
    rng = Rails.root.join('data', 'xml4docx2', 'xml4docx.rng')
    abort unless system("trang #{rnc} #{rng}")
    @relaxng = Nokogiri::XML::RelaxNG(File.read(rng))
  end

  def check(src)
    puts "check_xml4docx 檢查 XML 格式"
    Dir.glob("#{src}/**/*.xml", sort: true) do
      do_file(it)
    end
    puts
    check_as_text('T/T10/T10n0293/T10n0293_040.xml', /0851a17.*住持沙門如賢/m)
    check_as_text('T/T54/T54n2128/T54n2128_063.xml', /百一羯磨十卷.*0725a24/m)
    check_as_text('T/T55/T55n2149/T55n2149_005.xml', /0272b08.*0272b09/m)
    check_as_text('T/T55/T55n2154/T55n2154_011.xml', /0592b06.*0592b07/m)
  end

  private

  def check_as_text(fn, regex)
    xml_path = Rails.root.join('data', 'xml4docx2', fn)
    unless File.exist?(xml_path)
      abort "檔案不存在: #{xml_path}"
    end

    puts "check: #{xml_path}"
    text = File.read(xml_path)
    if text !~ regex
      puts "Error: 行號錯誤"
      puts "File: #{fn}"
      puts "應為：#{regex.source}"
      abort
    end
  end

  def do_file(xml_path)
    print "\rcheck_xml4docx #{xml_path}  "

    @doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    unless @doc.errors.empty?
      abort "XML not well-form: #{@doc.errors}"
    end

    errors = @relaxng.validate(@doc)
    unless errors.empty?
      abort "\nXML not valid ❌"
    end

    traverse(@doc.root)

    abort "仍有 seg 包 seg" if @doc.at_xpath('//seg/seg')
  end

  def e_footnote(e)
    case e.parent.name
    when 'font'
      warn "footnote 在 font 裡面, text: #{e.text}, lb: #{$lb}"
    when 'cell', 'p', 'seg'
    else
      abort "footnote 不是在 p 裡面, parent: #{e.parent.name}, text: #{e.text}, lb: #{$lb}"
    end
  end

  def e_item(e)
    abort "item 下面沒有 p, lb: #{$lb}" if e.at_xpath('p').nil?
    traverse(e)
  end
  
  def e_p(e)
    if e.key?('rend')
      rend = e['rend']
      if @doc.at_xpath("//styles/style[@name='#{rend}']").nil?
        warn "p rend: #{rend.inspect} 檔頭 style 未定義" 
      end
    end
    
    if e.text.empty? and e.at_xpath('graphic').nil?
      abort "\np 的內容是空的, lb: #{$lb}"
    end

    traverse(e)
  end

  def e_seg(e)
    if e.key?('rend')
      rend = e['rend']
      if @styles[rend].nil?
        puts "seg rend: #{rend.inspect} 未定義" 
        puts $fn
        puts "text: #{e.text}"
        abort
      end
    end

    traverse(e)
  end

  def traverse(e)
    if e.text?
      s = e.text.gsub(/\s+/, '')
      return if s.empty?
      warn "文字直接出現在 body 下: #{e.text.inspect}" if e.parent.name == 'body'
      return
    end

    e.children.each do |c|
      if c.comment?
        $lb = c.text.sub(/lb: /, '')
      end
      case c.name
      when 'footnote' then e_footnote(c)
      when 'item' then e_item(c)
      when 'p'    then e_p(c)
      when 'seg' then e_seg(c)
      else
        traverse(c)
      end
    end
  end

  def warn(msg)
    puts msg
    @log.puts msg
  end
end
