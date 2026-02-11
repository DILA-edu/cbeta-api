# 檢查 xml4docx 檔案 是否正確
class CheckXMLForDocx
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @styles = YAML.load_file(fn)

    fn = Rails.root.join('log', 'check_xml4docx.log')
    @log = File.open(fn, 'w')

    rnc = Rails.root.join('data-static', 'schema', 'xml4docx.rnc')
    rng = Rails.root.join('data', 'xml4docx2', 'xml4docx.rng')
    cmd = "trang #{rnc} #{rng}"
    puts cmd
    system(cmd)
    @relaxng = Nokogiri::XML::RelaxNG(File.read(rng))
  end

  def check(src)
    time_start = Time.now
    puts "check_xml4docx 檢查 XML 格式"
    Dir.glob("#{src}/**/*.xml", sort: true) do
      do_file(it)
    end
    puts
    check_as_text('T/T09/T09n0262/T09n0262_007.xml', /伏遇.*<lb\/>.*亡夫/m)
    check_as_text('T/T10/T10n0293/T10n0293_001.xml', /0661a04.*<footnote>.*0661a05/m)
    check_as_text('T/T10/T10n0293/T10n0293_040.xml', /0851a17.*住持沙門如賢/m)
    check_as_text('T/T10/T10n0299/T10n0299_002.xml', /0892c09.*?<footnote><font name="sidd">先<\/font>\(ra\)【大】，<font name="sidd">刑<\/font>\(re\)【宋】【元】【明】<\/footnote><font name="sidd">先<\/font><lb\/>\n?\(ra\).*?0892c10/m)
    check_as_text('T/T18/T18n0860/T18n0860_001.xml', /183b08.*<seg rend="corr"><font name="sidd">巧<\/font><\/seg><lb\/>\s*<seg rend="corr">\(na\)<\/seg>/m)
    check_as_text('T/T18/T18n0864A/T18n0864A_001.xml', /0196a15.*部嚕唵.*0196a16/m)
    check_as_text('T/T18/T18n0867/T18n0867_001.xml', /0254a29.*?怛.*?0254b02/m)
    check_as_text('T/T18/T18n0868/T18n0868_002.xml', /0274b18.*』.*0274b19/m)
    check_as_text('T/T20/T20n1096/T20n1096_001.xml', /0420c26.*0420c27/m)
    check_as_text('T/T20/T20n1168B/T20n1168B_001.xml', /0676c16.*?<cell>如<lb\/>\n?<font name="sidd">珫<\/font><lb\/>\n?\(e\)<\/cell>.*?0676c18/m)
    check_as_text('T/T21/T21n1299/T21n1299_001.xml', /虛室奎胃畢參鬼星翼角氐心<\/p>/m)
    check_as_text('T/T21/T21n1299/T21n1299_001.xml', /0388a16.*\(新演如左.*0388a17/m)
    check_as_text('T/T22/T22n1431/T22n1431_001.xml', /及法比丘僧，.*<lb\/>.*今演毘尼法/m)
    check_as_text('T/T48/T48n2023/T48n2023_010.xml', /群生得光輝。<lb\/>\n?一萬八千土/m)    
    check_as_text('T/T53/T53n2122/T53n2122_053.xml', /\(如四分律云/m)
    check_as_text('T/T53/T53n2122/T53n2122_053.xml', /\(故佛本行經云/m)
    check_as_text('T/T53/T53n2122/T53n2122_053.xml', /0683b02.*(?!\()爾時舍利弗.*0683b03/m)
    check_as_text('T/T54/T54n2128/T54n2128_063.xml', /百一羯磨十卷.*0725a24/m)
    check_as_text('T/T54/T54n2132/T54n2132_001.xml', /<font rend="corr" name="sidd">裶<\/font>/)
    check_as_text('T/T54/T54n2133A/T54n2133A_001.xml', /<footnote>uparopara\?<\/footnote><font name="sidd">裶/)
    check_as_text('T/T54/T54n2133A/T54n2133A_001.xml', /1190a22.*?<cell><font name="sidd">辱絞箌<\/font><lb\/>\n?\(sva\)\(rga\)<lb\/>\n?天<\/cell>.*?1190a24/m)
    check_as_text('T/T54/T54n2133A/T54n2133A_001.xml', /1194c17.*?<font name="sidd">巴<\/font>\(ṭa\)〔<font name="sidd">一<\/font>\(ka\)〕/m)
    check_as_text('T/T55/T55n2149/T55n2149_005.xml', /0272b08.*0272b09/m)
    check_as_text('T/T55/T55n2154/T55n2154_011.xml', /0592b06.*0592b07/m)
    check_as_text('T/T55/T55n2154/T55n2154_013.xml', /0622a12.*\(出翻經圖單本.*0622a13/m)
    check_as_text('X/X14/X14n0288/X14n0288_001.xml', /0006a13.*<footnote>真鑑曰.*0006a14/m)
    
    puts "\n未發現錯誤"
    puts "花費時間：" + ChronicDuration.output((Time.now - time_start).round(2))
  end

  private

  def check_as_text(fn, regex)    
    xml_path = Rails.root.join('data', 'xml4docx2', fn)
    unless File.exist?(xml_path)
      abort "檔案不存在: #{xml_path}"
    end

    print "\rcheck: #{xml_path}  "
    text = File.read(xml_path)
    if text !~ regex
      puts "Error: check_as_text"
      puts "File: #{fn}"
      puts "應該要 match pattern：#{regex.source}"
      abort
    end
  end

  def do_file(xml_path)
    print "\rcheck_xml4docx #{File.basename(xml_path)}  "

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
    if e.at_xpath('list | p').nil?
      abort "item 下面沒有 p, lb: #{$lb}, item: #{e.to_xml}" 
    end
    traverse(e)
  end
  
  def e_p(e)
    if e.key?('rend')
      rend = e['rend']
      if @doc.at_xpath("//styles/style[@name='#{rend}']").nil?
        warn "p rend: #{rend.inspect} 檔頭 style 未定義" 
      end
    end
    
    s = e.text.gsub(/\s/, '')
    if s.empty? and e.at_xpath('graphic').nil?
      abort "\np 的內容是空的, lb: #{$lb}, xml: #{e.to_xml}"
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

  def error(msg)
    location = caller_locations.first
    file = File.basename(location.path)
    abort "#{file}:#{location.lineno}, #{msg}"
  end

  def warn(msg)
    puts msg
    @log.puts msg
  end
end
